# Make sure RUBY_VERSION matches the Ruby version in .ruby-version and Gemfile
ARG RUBY_VERSION=3.3.0
FROM public.ecr.aws/docker/library/ruby:$RUBY_VERSION-slim as base

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
EXPOSE 9292

# Create necessary directories
RUN mkdir -p /app/db /app/csv /app/archive
RUN ruby setup.rb

# Start the Sinatra application
CMD ["rackup"]