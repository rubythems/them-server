# frozen_string_literal: true

require "sequel"
require "rom"
require "hanami/db/testing"

module Them
  module Server
    module Database
      class << self
        def database_url
          env = ENV["HANAMI_ENV"] || ENV["RACK_ENV"] || "development"
          root = File.expand_path("..", __dir__)
          resolve_database_url(root, env)
        end

        def db
          env = ENV["HANAMI_ENV"] || ENV["RACK_ENV"] || "development"
          return @db if env != "test" && defined?(@db) && @db

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

          database_url = resolve_database_url(root, env)

          config = ROM::Configuration.new(:sql, database_url)

          relations_path = File.join(root, "app", "relations")
          require File.join(root, "app", "db", "relation.rb")
          require File.join(relations_path, "owners.rb")
          require File.join(relations_path, "gems.rb")
          require File.join(relations_path, "scopes.rb")
          require File.join(relations_path, "scope_owners.rb")
          require File.join(relations_path, "gem_owners.rb")

          config.register_relation(Them::Server::Relations::Owners)
          config.register_relation(Them::Server::Relations::Gems)
          config.register_relation(Them::Server::Relations::Scopes)
          config.register_relation(Them::Server::Relations::ScopeOwners)
          config.register_relation(Them::Server::Relations::GemOwners)

          @rom = ROM.container(config)
        end

        def migrate
          Sequel.extension(:migration)
          Sequel::Migrator.run(db, "config/db/migrate")
        end

        private

        def resolve_database_url(root, env)
          raw_url = ENV["DATABASE_URL"].to_s.strip
          if raw_url.empty?
            db_file = ENV["THEM_SERVER_DB"].to_s.strip
            db_file = File.join(root, "config", "db", "them_server.sqlite") if db_file.empty?
            raw_url = "sqlite://#{db_file}"
          end

          raw_url = Hanami::DB::Testing.database_url(raw_url) if env == "test"
          raw_url = parallel_test_database_url(raw_url) if env == "test"
          expand_sqlite_database_url(raw_url, root)
        end

        def expand_sqlite_database_url(raw_url, root)
          return raw_url unless raw_url.start_with?("sqlite://")

          db_path = raw_url.sub("sqlite://", "")
          return raw_url if db_path == ":memory:"

          db_path = File.join(root, db_path) unless db_path.start_with?("/")
          "sqlite://#{db_path}"
        end

        def parallel_test_database_url(raw_url)
          test_env_number = ENV["TEST_ENV_NUMBER"].to_s.strip
          return raw_url if test_env_number.empty? || !raw_url.start_with?("sqlite://")

          db_path = raw_url.sub("sqlite://", "")
          return raw_url if db_path == ":memory:"

          ext = File.extname(db_path)
          base = ext.empty? ? db_path : db_path.delete_suffix(ext)
          "sqlite://#{base}_#{test_env_number}#{ext}"
        end
      end
    end
  end
end
