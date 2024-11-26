require 'sqlite3'
require 'bcrypt'
require 'fileutils'

DB_PATH = 'db/development.sqlite3'

# Ensure the db, csv, and archive directories exist
['db', 'csv', 'archive'].each do |dir|
  FileUtils.mkdir_p(dir)
end

# Only proceed if database doesn't exist
if !File.exist?(DB_PATH)

  # Create and setup the database
  db = SQLite3::Database.new(DB_PATH)

  # Create users table
  db.execute <<-SQL
    CREATE TABLE IF NOT EXISTS users (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      username TEXT UNIQUE NOT NULL,
      password_hash TEXT NOT NULL,
      force_password_change BOOLEAN DEFAULT 1
    );
  SQL

  # Create default admin user with password 'admin'
  default_password = BCrypt::Password.create('admin')
  db.execute("INSERT OR IGNORE INTO users (username, password_hash) VALUES (?, ?)", ['admin', default_password])

  puts "Database setup complete!"
else
  puts "Database already exists, skipping setup."
end 
# ruby setup.rb