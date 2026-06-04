# frozen_string_literal: true

# External RSpec & related config
require "kettle/test/rspec"

require "pathname"
SPEC_ROOT = Pathname(__dir__).realpath.freeze

ENV["HANAMI_ENV"] ||= "test"
require "hanami/prepare"

SPEC_ROOT.glob("support/**/*.rb").each { |f| require f }

# Internal ENV config
require_relative "config/debug"
require_relative "config/vcr"

# Config for development dependencies of this library
# i.e., not configured by this library
#
# Simplecov & related config (must run BEFORE any other requires)
# NOTE: Gemfiles for older rubies won't have kettle-soup-cover.
#       The rescue LoadError handles that scenario.
begin
  require "kettle-soup-cover"
  require "simplecov" if Kettle::Soup::Cover::DO_COV # `.simplecov` is run here!
rescue LoadError => error
  # check the error message and re-raise when unexpected
  raise error unless error.message.include?("kettle")
end

# This library
require "them/server"

# this library
require "them/server"

# Load database configuration
require_relative "../config/database"

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = ".rspec_status"

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  # Database cleanup
  config.before(:suite) do
    # Create test database
    Them::Server::Database.migrate
  end

  config.before do |example|
    # Skip database cleanup for E2E tests that manage their own database state
    # Check both the type metadata and if the example is tagged with :skip_db_cleanup
    next if example.metadata[:type] == :e2e || example.metadata[:skip_db_cleanup]

    # Clean database before each test
    db = Them::Server::Database.db
    # Federation tables first (FKs)
    db[:federated_gems].delete if db.table_exists?(:federated_gems)
    db[:known_servers].delete if db.table_exists?(:known_servers)
    # Existing tables
    db[:gem_owners].delete
    db[:scope_owners].delete
    db[:gems].delete
    db[:owners].delete
    db[:scopes].delete
  end
end
