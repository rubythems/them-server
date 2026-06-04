# frozen_string_literal: true

require_relative "../database"

Hanami.app.configure_provider :db do
  config.gateway :default do |gateway|
    gateway.database_url = Them::Server::Database.database_url
  end
end
