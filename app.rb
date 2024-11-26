require 'sinatra'
require 'rufus-scheduler'
require 'json'
require 'csv'
require 'time'
require 'net/http'
require 'dotenv'
require 'fileutils'
require 'securerandom'
require_relative 'models/user'
require 'bcrypt'
require 'sinatra/flash'

Dotenv.load

# Main application class
class App < Sinatra::Base
  register Sinatra::Flash

  configure do
    set :scheduler, Rufus::Scheduler.new # Initialize scheduler
    set :csv_path, File.join(Dir.pwd, 'csv') # Default path for CSV files
    set :api_url, ENV['API_URL'] || 'http://localhost:3000/api/v1/clock_entries/bulk' # Default API URL
    set :schedule_interval, ENV['SCHEDULE_INTERVAL'] || '1m' # Default scheduler interval
    set :archive, true
    set :archive_path, File.join(Dir.pwd, 'archive') # Use current working directory
    # Create archive directory if it doesn't exist
    FileUtils.mkdir_p(settings.archive_path) unless Dir.exist?(settings.archive_path)
    # Ensure directories exist
    FileUtils.mkdir_p(settings.csv_path) unless Dir.exist?(settings.csv_path)
    # Generate a proper secret key
    secret_key = ENV['SESSION_SECRET'] || SecureRandom.hex(64)
    enable :sessions
    set :session_secret, secret_key
  end

  settings.scheduler.every settings.schedule_interval do
    puts "Scheduler triggered at #{Time.now}"
    App.process_csv_files
  end

  class << self
    def process_csv_files
      begin
        Dir.glob(File.join(settings.csv_path, 'clock_entries*.csv')).each do |file|
          filename = File.basename(file)
          puts "Processing file: #{filename}"

          content = File.read(file)
          json_data = parse_csv_to_json(content)
          bulk_data = { entries: json_data }

          begin
            response = send_data_to_api(bulk_data)
            
            if response.is_a?(Net::HTTPSuccess)
              puts "Successfully sent #{json_data.length} entries to #{settings.api_url}"
              if settings.archive
                FileUtils.cp(file, File.join(settings.archive_path, filename))
                File.delete(file)
              end
            else
              puts "Error from API (#{response.code}): #{response.body}"
            end
          rescue Errno::ECONNREFUSED
            puts "Warning: Could not connect to API at #{settings.api_url}. Is it running?"
            return false
          rescue => e
            puts "Error processing file #{filename}: #{e.message}"
            return false
          end
        end
        true
      rescue => e
        puts "Error in process_csv_files: #{e.message}"
        false
      end
    end

    def parse_csv_to_json(content)
      csv = CSV.parse(content, headers: true, col_sep: ';')
      csv.map do |row|
        row = row.to_h.transform_keys! { |key| key.strip.downcase.gsub(/\s+/, '_') }
        row.transform_values! { |value| value.is_a?(String) ? value.strip.gsub(/[\t\\]/, '') : value }
        {
          user_id: row['person_code'],
          time: "#{row['date']}T#{row['time']}",
          clock_entry_type: row['attendance_status'].downcase,
          method: row['authentication_mode'],
          device_serial: row['device_serial_no.']
        }
      end
    end

    def send_data_to_api(data)
      uri = URI(settings.api_url)
      
      http = Net::HTTP.new(uri.host, uri.port)
      http.open_timeout = 5  # Connection timeout
      http.read_timeout = 30 # Read timeout
      http.use_ssl = uri.scheme == 'https'
      
      request = Net::HTTP::Post.new(uri.path)
      request['Content-Type'] = 'application/json'
      request['X-API-Key'] = ENV['API_KEY']
      request.body = data.to_json
      
      http.request(request)
    rescue Errno::ECONNREFUSED => e
      raise e
    rescue => e
      puts "Error in API request: #{e.message}"
      raise e
    end

    # Add these helper methods for scheduler status checking
    def rufus_running?(scheduler)
      return false unless scheduler.up?
      return false unless scheduler.thread&.alive?
      true
    end

    def scheduler_status
      return false unless defined?(Rufus::Scheduler)
      
      ObjectSpace.each_object do |o|
        next unless o.is_a?(Rufus::Scheduler)
        return true if rufus_running?(o)
      end
      false
    end
  end

  at_exit do
    settings.scheduler.shutdown
  end

  # Add these helper methods
  helpers do
    def current_user
      @current_user ||= User.find(session[:user_id]) if session[:user_id]
    end

    def authenticated?
      !current_user.nil?
    end

    def require_authentication
      redirect '/login' unless authenticated?
    end
  end

  # Add these routes before your existing routes
  get '/login' do
    redirect '/' if authenticated?
    erb :login
  end

  post '/login' do
    user = User.authenticate(params[:username], params[:password])
    if user
      session[:user_id] = user.id
      if user.force_password_change
        redirect '/change_password'
      else
        redirect '/'
      end
    else
      @error = "Invalid username or password"
      erb :login
    end
  end

  get '/change_password' do
    require_authentication
    erb :change_password
  end

  post '/change_password' do
    require_authentication
    if params[:new_password] == params[:confirm_password]
      current_user.update_password(params[:new_password])
      redirect '/'
    else
      @error = "Passwords don't match"
      erb :change_password
    end
  end

  get '/logout' do
    session.clear
    redirect '/login'
  end

  # Modify your existing routes to require authentication
  get '/' do
    require_authentication
    @status = App.scheduler_status
    @settings = {
      api_url: settings.api_url,
      schedule_interval: settings.schedule_interval,
    }
    erb :'index.html'
  end

  post '/settings' do
    require_authentication
    settings.api_url = params[:api_url] if params[:api_url]
    settings.schedule_interval = params[:schedule_interval] if params[:schedule_interval]
    
    redirect '/'
  end

  post '/scheduler/toggle' do
    require_authentication
    if App.scheduler_status
      settings.scheduler.shutdown
    else
      settings.scheduler = Rufus::Scheduler.new
      settings.scheduler.every settings.schedule_interval do
        puts "Scheduler triggered at #{Time.now}"
        App.process_csv_files
      end
    end
    redirect '/'
  end

  post '/process' do
    require_authentication
    if App.process_csv_files
      flash[:success] = "CSV files processed successfully"
    else
      flash[:error] = "Error processing CSV files. Check the logs for details."
    end
    redirect '/'
  end
end

