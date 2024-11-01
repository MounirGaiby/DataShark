require 'sinatra'
require 'rufus-scheduler'
require 'sqlite3'
require 'json'
require 'csv'
require 'time'
require 'net/http'
require 'dotenv'
require 'fileutils'

Dotenv.load

# Main application class
class App < Sinatra::Base
  configure do
    set :scheduler, Rufus::Scheduler.new # Initialize scheduler
    set :db, SQLite3::Database.new(ENV['DATABASE_PATH'] || '/db/db.sqlite3') # Use in-memory database if no path is provided
    set :csv_path, ENV['CSV_PATH'] || '/csv' # Default path for CSV files
    set :api_url, ENV['API_URL'] || 'http://172.25.71.43:3000/api/v1/clock_entries/bulk' # Default API URL
    set :schedule_interval, ENV['SCHEDULE_INTERVAL'] || '1m' # Default scheduler interval
    set :archive, ENV['ARCHIVE'] || false # Default archive setting
    set :archive_path, ENV['ARCHIVE_PATH'] || File.join(Dir.pwd, '/archive') # Default archive path
    # Create archive directory if it doesn't exist
    FileUtils.mkdir_p(settings.archive_path) unless Dir.exist?(settings.archive_path)

    settings.db.execute <<-SQL
      CREATE TABLE IF NOT EXISTS read_files (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        filename TEXT,
        time TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      );
    SQL
  end

  settings.scheduler.every settings.schedule_interval do
    puts "Scheduler triggered at #{Time.now}"
    App.process_csv_files
  end

  class << self
    def process_csv_files
      Dir.glob(File.join(settings.csv_path, 'clock_entries*.csv')).each do |file|
        filename = File.basename(file)

        content = File.read(file)
        json_data = parse_csv_to_json(content)
        bulk_data = { entries: json_data }

        response = send_data_to_api(bulk_data)

        if response.code == '200'
          puts "Successfully sent #{json_data.length} entries to #{settings.api_url}"
          settings.db.execute('INSERT INTO read_files (filename) VALUES (?)', filename)
          if settings.archive
            FileUtils.cp(file, File.join(settings.archive_path, filename))
            File.delete(file)
          end
        else
          puts "Error sending data to #{settings.api_url}:"
          puts response.body
        end
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
      http.use_ssl = uri.scheme == 'https'
      request = Net::HTTP::Post.new(uri.path, {
                                      'Content-Type' => 'application/json',
                                      'X-API-Key' => ENV['API_KEY']
                                    })
      request.body = data.to_json
      http.request(request)
    end
  end

  at_exit do
    settings.scheduler.shutdown
  end
end
