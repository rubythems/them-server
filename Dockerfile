# syntax=docker/dockerfile:1
FROM ruby:3.4-alpine

ENV APP_HOME=/app \
    BUNDLE_WITHOUT="development test" \
    RACK_ENV=production \
    HANAMI_ENV=production \
    HANAMI_PORT=2300

RUN apk add --no-cache build-base git sqlite sqlite-dev zlib-dev yaml-dev
RUN apk add --no-cache libyaml

RUN gem update --system

WORKDIR $APP_HOME

# Copy the minimum needed for bundle install
COPY gemfiles/ gemfiles/
COPY Gemfile Gemfile.lock them-server.gemspec ./

# Install dependencies (will be cached unless gemspec/Gemfile change)
RUN bundle install

# Copy the app
COPY . $APP_HOME

EXPOSE 2300
CMD ["bundle", "exec", "rackup", "-p", "2300", "-E", "production", "--host", "0.0.0.0"]
