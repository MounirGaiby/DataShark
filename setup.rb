require 'sqlite3'
require 'bcrypt'
require 'fileutils'

# Ensure the db directory exists
FileUtils.mkdir_p('db')

# Create and setup the database
db = SQLite3::Database.new('db/development.sqlite3')

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
# ruby setup.rb