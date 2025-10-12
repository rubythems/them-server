# frozen_string_literal: true

require "sequel"
require "rom"

module Gem
  module Server
    module Database
      class << self
        def db
          # Don't cache connections in test environment to avoid stale data across processes
          env = ENV["HANAMI_ENV"] || ENV["RACK_ENV"] || "development"
          return @db if env != "test" && defined?(@db) && @db

          # Build absolute path to the sqlite DB to avoid CWD-dependent mismatches
          root = File.expand_path("..", __dir__) # project root

          # Determine database file based on environment
          default_db_file = if env == "test"
            File.join(root, "db", "gem_server_test.sqlite")
          else
            File.join(root, "db", "gem_server.db")
          end

          db_file = ENV["GEM_SERVER_DB"].to_s.strip
          db_file = default_db_file if db_file.empty?

          connection = Sequel.connect("sqlite://#{db_file}")

          # Enable WAL mode for better concurrent access in test environment
          if env == "test"
            connection.run("PRAGMA journal_mode=WAL")
            connection.run("PRAGMA synchronous=NORMAL")
            # Reduce busy timeout to avoid long waits, but allow some retry time
            connection.run("PRAGMA busy_timeout=5000")
          end

          @db = connection if env != "test"
          connection
        end

        def rom
          return @rom if defined?(@rom) && @rom

          env = ENV["HANAMI_ENV"] || ENV["RACK_ENV"] || "development"
          root = File.expand_path("..", __dir__)

          default_db_file = if env == "test"
            File.join(root, "db", "gem_server_test.sqlite")
          else
            File.join(root, "db", "gem_server.db")
          end

          db_file = ENV["GEM_SERVER_DB"].to_s.strip
          db_file = default_db_file if db_file.empty?

          config = ROM::Configuration.new(:sql, "sqlite://#{db_file}")

          # Manually register relations from app/relations
          relations_path = File.join(root, "app", "relations")
          if Dir.exist?(relations_path)
            Dir[File.join(relations_path, "*.rb")].each do |file|
              require file
            end
          end

          # Register all loaded relation classes with ROM
          config.register_relation(Gem::Server::Relations::Owners)
          config.register_relation(Gem::Server::Relations::Gems)
          config.register_relation(Gem::Server::Relations::Scopes)
          config.register_relation(Gem::Server::Relations::ScopeOwners)
          config.register_relation(Gem::Server::Relations::GemOwners)

          @rom = ROM.container(config)
        end

        def migrate
          Sequel.extension(:migration)
          Sequel::Migrator.run(db, "db/migrations")
        end
      end
    end
  end
end
