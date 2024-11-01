# Use the official Ruby image from the Docker Hub
FROM ruby:3.3.0

# Install dependencies
RUN apt-get update -qq && apt-get install -y build-essential libsqlite3-dev

# Set the working directory
WORKDIR /app

# Copy the Gemfile and Gemfile.lock into the container
COPY Gemfile* /app/

# Install the gems specified in the Gemfile
RUN bundle install

# Copy the rest of the application code into the container
COPY . /app

# Expose the port the app runs on
EXPOSE 4567

# Create necessary directories
RUN mkdir -p /app/db /app/csv /app/archive

# Start the Sinatra application
CMD ["rackup"]