require 'sqlite3'
require 'bcrypt'

class User
  attr_reader :id, :username, :force_password_change

  def initialize(attributes)
    return unless attributes
    @id = attributes['id']
    @username = attributes['username']
    @force_password_change = attributes['force_password_change'] == 1
  end

  def self.db
    @db ||= begin
      db = SQLite3::Database.new('db/development.sqlite3')
      db.results_as_hash = true
      db
    end
  end

  def self.authenticate(username, password)
    user = db.execute("SELECT * FROM users WHERE username = ? LIMIT 1", [username]).first
    return nil unless user
    return nil unless BCrypt::Password.new(user['password_hash']) == password
    new(user)
  end

  def self.find(id)
    return nil unless id
    user = db.execute("SELECT * FROM users WHERE id = ? LIMIT 1", [id]).first
    new(user) if user
  end

  def update_password(new_password)
    password_hash = BCrypt::Password.create(new_password)
    self.class.db.execute(
      "UPDATE users SET password_hash = ?, force_password_change = 0 WHERE id = ?",
      [password_hash, @id]
    )
  end
end 