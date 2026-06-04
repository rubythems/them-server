# frozen_string_literal: true

# External RSpec & related config
require "kettle/test/rspec"

require "pathname"
require "zlib"
SPEC_ROOT = Pathname(__dir__).realpath.freeze

ENV["HANAMI_ENV"] ||= "test"
parallel_suffix = ENV["TEST_ENV_NUMBER"].to_s.strip
appraisal_suffix = Zlib.crc32(ENV["BUNDLE_GEMFILE"].to_s).to_s
spec_gems_dir = ["tmp/spec_gems", parallel_suffix, appraisal_suffix].reject(&:empty?).join("_")
ENV["THEM_SERVER_GEMS_DIR"] ||= File.expand_path(spec_gems_dir, SPEC_ROOT.parent)
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

  config.prepend_before do |example|
    # Skip database cleanup for E2E tests that manage their own database state
    # Check both the type metadata and if the example is tagged with :skip_db_cleanup
    next if example.metadata[:type] == :e2e || example.metadata[:skip_db_cleanup]

    db = Them::Server::Database.db
    db.run("PRAGMA foreign_keys = OFF") if db.database_type == :sqlite
    %i[
      account_remember_keys
      account_login_change_keys
      account_verification_keys
      account_password_reset_keys
      accounts
      gem_owners
      scope_owners
      federated_gems
      known_servers
      gems
      owners
      scopes
    ].each do |table|
      db[table].delete if db.table_exists?(table)
    end
  ensure
    db&.run("PRAGMA foreign_keys = ON") if db&.database_type == :sqlite
  end
end
