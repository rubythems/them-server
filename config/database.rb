# frozen_string_literal: true

require "sequel"
require "rom"

module Gem
  module Server
    module Database
      class << self
        def db
          env = ENV["HANAMI_ENV"] || ENV["RACK_ENV"] || "development"
          return @db if env != "test" && defined?(@db) && @db

          root = File.expand_path("..", __dir__)

          database_url = ENV["DATABASE_URL"].to_s.strip
          if database_url.empty?
            default_db_file = env == "test" ? File.join(root, "config", "db", "them_server_test.sqlite") : File.join(root, "config", "db", "them_server.db")
            db_file = ENV["GEM_SERVER_DB"].to_s.strip
            db_file = default_db_file if db_file.empty?
            database_url = "sqlite://#{db_file}"
          elsif database_url.start_with?("sqlite://")
            # Expand relative paths to absolute paths
            db_path = database_url.sub("sqlite://", "")
            unless db_path.start_with?("/") || db_path == ":memory:"
              db_path = File.join(root, db_path)
            end
            database_url = "sqlite://#{db_path}"
          end

          connection = Sequel.connect(database_url)

          if env == "test"
            connection.run("PRAGMA journal_mode=WAL") rescue nil
            connection.run("PRAGMA synchronous=NORMAL") rescue nil
            connection.run("PRAGMA busy_timeout=5000") rescue nil
          end

          @db = connection if env != "test"
          connection
        end

        def rom
          return @rom if defined?(@rom) && @rom

          env = ENV["HANAMI_ENV"] || ENV["RACK_ENV"] || "development"
          root = File.expand_path("..", __dir__)

          database_url = ENV["DATABASE_URL"].to_s.strip
          if database_url.empty?
            default_db_file = env == "test" ? File.join(root, "config", "db", "them_server_test.sqlite") : File.join(root, "config", "db", "them_server.db")
            db_file = ENV["GEM_SERVER_DB"].to_s.strip
            db_file = default_db_file if db_file.empty?
            database_url = "sqlite://#{db_file}"
          elsif database_url.start_with?("sqlite://")
            # Expand relative paths to absolute paths
            db_path = database_url.sub("sqlite://", "")
            unless db_path.start_with?("/") || db_path == ":memory:"
              db_path = File.join(root, db_path)
            end
            database_url = "sqlite://#{db_path}"
          end

          config = ROM::Configuration.new(:sql, database_url)

          relations_path = File.join(root, "app", "relations")
          require File.join(relations_path, "owners.rb")
          require File.join(relations_path, "gems.rb")
          require File.join(relations_path, "scopes.rb")
          require File.join(relations_path, "scope_owners.rb")
          require File.join(relations_path, "gem_owners.rb")

          config.register_relation(Gem::Server::Relations::Owners)
          config.register_relation(Gem::Server::Relations::Gems)
          config.register_relation(Gem::Server::Relations::Scopes)
          config.register_relation(Gem::Server::Relations::ScopeOwners)
          config.register_relation(Gem::Server::Relations::GemOwners)

          @rom = ROM.container(config)
        end

        def migrate
          Sequel.extension(:migration)
          Sequel::Migrator.run(db, "config/db/migrate")
        end
      end
    end
  end
end
