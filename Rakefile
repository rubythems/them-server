# frozen_string_literal: true

$LOAD_PATH.unshift(File.expand_path("lib", __dir__))
require "bundler/setup"

# kettle-dev Rakefile v1.1.32 - 2025-10-07
# Ruby 2.3 (Safe Navigation) or higher required
#
# MIT License (see License.txt)
#
# Copyright (c) 2025 Peter H. Boling (galtzo.com)
#
# Expected to work in any project that uses Bundler.
#
# Sets up tasks for appraisal, floss_funding, rspec, minitest, rubocop, reek, yard, and stone_checksums.
#
# rake appraisal:update                       # Update Appraisal gemfiles and run RuboCop...
# rake bench                                  # Run all benchmarks (alias for bench:run)
# rake bench:list                             # List available benchmark scripts
# rake bench:run                              # Run all benchmark scripts (skips on CI)
# rake build:generate_checksums               # Generate both SHA256 & SHA512 checksums i...
# rake bundle:audit:check                     # Checks the Gemfile.lock for insecure depe...
# rake bundle:audit:update                    # Updates the bundler-audit vulnerability d...
# rake ci:act[opt]                            # Run 'act' with a selected workflow
# rake coverage                               # Run specs w/ coverage and open results in...
# rake default                                # Default tasks aggregator
# rake install                                # Build and install kettle-dev-1.0.0.gem in...
# rake install:local                          # Build and install kettle-dev-1.0.0.gem in...
# rake kettle:dev:install                     # Install kettle-dev GitHub automation and ...
# rake kettle:dev:template                    # Template kettle-dev files into the curren...
# rake reek                                   # Check for code smells
# rake reek:update                            # Run reek and store the output into the RE...
# rake release[remote]                        # Create tag v1.0.0 and build and push kett...
# rake rubocop_gradual                        # Run RuboCop Gradual
# rake rubocop_gradual:autocorrect            # Run RuboCop Gradual with autocorrect (onl...
# rake rubocop_gradual:autocorrect_all        # Run RuboCop Gradual with autocorrect (saf...
# rake rubocop_gradual:check                  # Run RuboCop Gradual to check the lock file
# rake rubocop_gradual:force_update           # Run RuboCop Gradual to force update the l...
# rake rubocop_gradual_debug                  # Run RuboCop Gradual
# rake rubocop_gradual_debug:autocorrect      # Run RuboCop Gradual with autocorrect (onl...
# rake rubocop_gradual_debug:autocorrect_all  # Run RuboCop Gradual with autocorrect (saf...
# rake rubocop_gradual_debug:check            # Run RuboCop Gradual to check the lock file
# rake rubocop_gradual_debug:force_update     # Run RuboCop Gradual to force update the l...
# rake spec                                   # Run RSpec code examples
# rake test                                   # Run tests
# rake yard                                   # Generate YARD Documentation
#

require "bundler/gem_tasks" if !Dir[File.join(__dir__, "*.gemspec")].empty?

# Define a base default task early so other files can enhance it.
desc "Default tasks aggregator"
task :default do
  puts "Default task complete."
end

# External gems that define tasks - add here!
require "kettle/dev"

### RELEASE TASKS
# Setup stone_checksums
begin
  require "stone_checksums"
rescue LoadError
  desc("(stub) build:generate_checksums is unavailable")
  task("build:generate_checksums") do
    warn("NOTE: stone_checksums isn't installed, or is disabled for #{RUBY_VERSION} in the current environment")
  end
end

require "hanami/rake_tasks"

# --- Database tasks (Sequel migrations) ---
require_relative "config/database"
require "sequel"

# Ensure migration extension is loaded when invoking Sequel::Migrator directly
Sequel.extension(:migration)

namespace :db do
  # Helper: determine current migration version for integer migrations
  def current_migration_version(db)
    if db.table_exists?(:schema_info)
      row = db[:schema_info].first
      (row && row[:version].to_i) || 0
    else
      0
    end
  end

  desc "Run database migrations"
  task :migrate do
    Gem::Server::Database.migrate
    db = Gem::Server::Database.db
    puts "Migrations complete. Current version: #{current_migration_version(db)}"
  end

  desc "Print current migration version"
  task :version do
    db = Gem::Server::Database.db
    puts current_migration_version(db)
  end

  desc "Rollback database by N steps (default 1). Usage: rake db:rollback[steps]"
  task :rollback, [:steps] do |_t, args|
    db = Gem::Server::Database.db
    current = current_migration_version(db)
    steps = (args[:steps] || "1").to_i
    target = [current - steps, 0].max
    Sequel::Migrator.run(db, "config/db/migrate", target: target)
    puts "Rolled back #{steps} step(s). Now at version: #{current_migration_version(db)}"
  end

  desc "Seed the database from config/db/seeds.rb"
  task :seed do
    seed_path = File.join(__dir__, "config/db/seeds.rb")
    if File.exist?(seed_path)
      require seed_path
      puts "Seed complete."
    else
      abort "No seeds file at #{seed_path}"
    end
  end

  desc "Reset the database (delete SQLite file, migrate, seed)"
  task :reset do
    db = Gem::Server::Database.db
    db.disconnect if db
    root = File.expand_path("..", __dir__)

    # Determine DB file path based on DATABASE_URL or GEM_SERVER_DB
    sqlite_file = nil
    database_url = ENV["DATABASE_URL"].to_s.strip
    if !database_url.empty?
      if database_url.start_with?("sqlite://")
        sqlite_file = database_url.sub("sqlite://", "")
      elsif database_url.start_with?("sqlite:")
        sqlite_file = database_url.sub("sqlite:", "")
      end
    end

    if sqlite_file.nil? || sqlite_file.empty?
      default_db_file = File.join(root, "config", "db", "them_server.db")
      db_file = ENV["GEM_SERVER_DB"].to_s.strip
      sqlite_file = db_file.empty? ? default_db_file : db_file
    end

    if sqlite_file && sqlite_file != ":memory:" && File.exist?(sqlite_file)
      File.delete(sqlite_file)
      puts "Deleted #{sqlite_file}"
    else
      puts "No SQLite file to delete (using DATABASE_URL=#{database_url.inspect})"
    end

    Rake::Task["db:migrate"].invoke
    begin
      Rake::Task["db:seed"].invoke
    rescue StandardError
      # seeding optional
    end
    puts "DB reset complete."
  end
end

# --- Federation helpers ---
namespace :federation do
  desc "List known servers"
  task :list_known do
    db = Gem::Server::Database.db
    rows = db[:known_servers].all
    if rows.empty?
      puts "No known servers"
    else
      rows.each do |r|
        puts "- #{r[:base_url]} subscribed=#{r[:subscribed]} last_seen=#{r[:last_seen_at]}"
      end
    end
  end

  desc "Seed a known server. Usage: rake federation:seed_known[base_url,public_key_b64]"
  task :seed_known, [:base_url, :public_key_b64] do |_t, args|
    base_url = args[:base_url].to_s.strip
    pub = args[:public_key_b64].to_s.strip
    abort "base_url is required" if base_url.empty?
    abort "public_key_b64 is required" if pub.empty?
    now = Time.now
    db = Gem::Server::Database.db
    row = db[:known_servers].where(base_url: base_url).first
    if row
      db[:known_servers].where(id: row[:id]).update(public_key_b64: pub, updated_at: now)
      puts "Updated known server: #{base_url}"
    else
      db[:known_servers].insert(base_url: base_url, public_key_b64: pub, subscribed: false, created_at: now, updated_at: now)
      puts "Added known server: #{base_url}"
    end
  end

  desc "Announce to a remote server. Usage: rake federation:announce[to_base_url,my_base_url]"
  task :announce, [:to_base_url, :my_base_url] do |_t, args|
    require "gem/server/federation_client"
    to_base = args[:to_base_url].to_s.strip
    my_base = args[:my_base_url].to_s.strip
    abort "to_base_url is required" if to_base.empty?
    Gem::Server::FederationClient.new.announce(to_base_url: to_base, my_base_url: my_base)
    puts "Announce sent to #{to_base}"
  end

  desc "Subscribe to a remote server. Usage: rake federation:subscribe[to_base_url,my_base_url]"
  task :subscribe, [:to_base_url, :my_base_url] do |_t, args|
    require "gem/server/federation_client"
    to_base = args[:to_base_url].to_s.strip
    my_base = args[:my_base_url].to_s.strip
    abort "to_base_url is required" if to_base.empty?
    Gem::Server::FederationClient.new.subscribe(to_base_url: to_base, my_base_url: my_base)
    puts "Subscribe sent to #{to_base}"
  end

  desc "Broadcast a stubbed gem record to all subscribed peers. Usage: rake federation:broadcast_stub[name,version,scope_path]"
  task :broadcast_stub, [:name, :version, :scope_path] do |_t, args|
    require "tempfile"
    require "gem/server/federation_broadcaster"
    name = (args[:name] || "demo").to_s
    version = (args[:version] || "0.1.0").to_s
    scope_path = (args[:scope_path] || "").to_s
    scope = scope_path.split("/").reject(&:empty?)

    prev = ENV["FEDERATION_BROADCAST"]
    ENV["FEDERATION_BROADCAST"] = "1"
    begin
      Tempfile.create(["stub", ".gem"]) do |tmp|
        tmp.binmode
        tmp.write("stubbed gem bytes for federation demo")
        tmp.flush
        Gem::Server::FederationBroadcaster.broadcast_gem(
          name: name,
          version: version,
          scope_path: scope,
          file_path: tmp.path,
        )
        scope_label = scope.empty? ? "(root)" : scope.join("/")
        puts "Broadcasted stub gem #{name}-#{version} (scope: #{scope_label})"
      end
    ensure
      ENV["FEDERATION_BROADCAST"] = prev
    end
  end
end

namespace :auth do
  desc "Create a Rodauth account and associated owner. Usage: rake auth:create_user[email,password,name]"
  task :create_user, [:email, :password, :name] do |_t, args|
    require 'bcrypt'
    require_relative 'config/database'
    email = args[:email].to_s.strip
    password = args[:password].to_s
    name = (args[:name].to_s.strip)
    abort "email is required" if email.empty?
    abort "password is required" if password.empty?
    name = email if name.empty?
    db = Gem::Server::Database.db
    now = Time.now
    existing = db[:accounts].where(email: email).first
    if existing
      puts "Account already exists: #{email}"
    else
      phash = BCrypt::Password.create(password)
      acc_id = db[:accounts].insert(email: email, status_id: 1, password_hash: phash, created_at: now, updated_at: now)
      puts "Created account ##{acc_id} for #{email}"
      if db.schema(:owners).map(&:first).include?(:account_id)
        db[:owners].insert(name: name, public_key: nil, api_key: nil, account_id: acc_id, created_at: now, updated_at: now)
        puts "Created owner for account ##{acc_id}"
      end
    end
  end
end
