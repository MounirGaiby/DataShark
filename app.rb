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
    set :scheduler, Rufus::Scheduler.new
    set :db, SQLite3::Database.new(ENV['DATABASE_PATH'])
    set :csv_path, ENV['CSV_PATH']
    set :api_url, ENV['API_URL']
    set :schedule_interval, ENV['SCHEDULE_INTERVAL']
    set :archive, ENV['ARCHIVE'] || false
    set :archive_path, ENV['ARCHIVE_PATH'] || File.join(Dir.pwd, 'archive')
    FileUtils.mkdir_p(settings.archive_path) unless Dir.exist?(settings.archive_path)

    settings.db.execute <<-SQL
      CREATE TABLE IF NOT EXISTS read_files (
        filename TEXT PRIMARY KEY
      );
    SQL
  end

  settings.scheduler.every settings.schedule_interval do
    App.process_csv_files
  end

  class << self
    def process_csv_files
      Dir.glob(File.join(settings.csv_path, 'clock_entries*.csv')).each do |file|
        filename = File.basename(file)

        next if settings.db.execute('SELECT 1 FROM read_files WHERE filename = ?', filename).any?

        content = File.read(file)
        json_data = parse_csv_to_json(content)
        bulk_data = { entries: json_data }

        puts bulk_data

        response = send_data_to_api(bulk_data)

        if response.code == '200'
          puts "Successfully sent #{json_data.length} entries to Rails API"
          settings.db.execute('INSERT INTO read_files (filename) VALUES (?)', filename)
          if settings.archive
            FileUtils.cp(file, File.join(settings.archive_path, filename))
            File.delete(file)
          end
        else
          puts "Error sending data to Rails API: #{response.body}"
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
          device: 'external',
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
