# frozen_string_literal: true

# kettle-jem:freeze
# To retain chunks of comments & code during kettle-jem templating:
# Wrap custom sections with freeze markers (e.g., as above and below this comment chunk).
# kettle-jem will then preserve content between those markers across template runs.
# kettle-jem:unfreeze

# them-server Rakefile v7.1.0 - 2026-08-04
# Ruby 2.3 (Safe Navigation) or higher required
#
# See LICENSE.md for license information.
#
# Copyright (c) 2026 Peter H. Boling (galtzo.com)
#
# Expected to work in any project that uses Bundler.
#
# Sets up tasks for appraisal2, floss_funding, kettle-jem, kettle-dev, rspec, minitest, rubocop_gradual, reek, yard, and stone_checksums.
#
# rake appraisal:install                      # Install Appraisal gemfiles (initial setup...
# rake appraisal:reset                        # Delete Appraisal lockfiles (gemfiles/*.gemfile.lock)
# rake appraisal:generate                     # Generate Appraisal gemfiles without resolving...
# rake appraisal:update                       # Generate and update Appraisal gemfiles
# rake bench                                  # Run all benchmarks (alias for bench:run)
# rake bench:list                             # List available benchmark scripts
# rake bench:run                              # Run all benchmark scripts (skips on CI)
# rake build:generate_checksums               # Generate both SHA256 & SHA512 checksums i...
# rake bundle:audit:check                     # Checks the Gemfile.lock for insecure depe...
# rake bundle:audit:update                    # Updates the bundler-audit vulnerability d...
# rake ci:act[opt]                            # Run 'act' with a selected workflow
# rake coverage                               # Run specs w/ coverage and open results in...
# rake default                                # Default tasks aggregator
# rake install                                # Build and install them-server-1.0.0.gem in...
# rake install:local                          # Build and install them-server-1.0.0.gem in...
# rake kettle:jem:install                     # Internal target used by `kettle-jem install`
# rake kettle:jem:selftest                    # Self-test: template them-server against itse...
# rake kettle:jem:template                    # Internal target used by scoped `kettle-jem template --only`
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
# rake yard:lint                              # Lint YARD Documentation
#

# simplecov:disable
require "bundler/gem_tasks" if !Dir[File.join(__dir__, "*.gemspec")].empty?
# simplecov:enable

# Define a base default task early so other files can enhance it.
desc "Default tasks aggregator"
task :default do
  puts "Default task complete."
end

# simplecov:disable
### MONOREPO FAMILY TASKS
if Dir.exist?(File.join(__dir__, "gems"))
  def family_gem_dirs
    Dir.glob(File.join(__dir__, "gems", "*", "*.gemspec"))
      .map { |path| File.dirname(path) }
      .uniq
      .sort_by { |path| File.basename(path) }
  end

  def run_kettle_family(*args)
    sh("bundle", "exec", "kettle-family", *args)
  end

  namespace :family do
    desc "List released Ruby subgems"
    task :list do
      family_gem_dirs.each { |path| puts File.basename(path) }
    end

    desc "Run release readiness checks for the Ruby gem family"
    task :readiness do
      run_kettle_family("check")
    end

    desc "Run tests for the Ruby gem family"
    task :test do
      run_kettle_family("test", "--execute")
    end

    desc "Run lint for the Ruby gem family"
    task :lint do
      run_kettle_family("lint", "--execute")
    end

    desc "Generate YARD docs for the Ruby gem family"
    task :docs do
      run_kettle_family("docs", "--execute")
    end

    desc "Report release state for the Ruby gem family"
    task :release_state do
      run_kettle_family("release-state")
    end

    desc "Run the Ruby gem family release planner"
    task :release do
      run_kettle_family("release")
    end

    desc "Execute the Ruby gem family release"
    task :release_execute do
      run_kettle_family("release", "--execute")
    end
  end
end
# simplecov:enable

# External gems that define tasks - add here!
begin
  require "kettle/dev"
  Kettle::Dev.install_tasks unless Kettle::Dev::RUNNING_AS == "rake"
rescue LoadError
  warn("NOTE: kettle-dev isn't installed, or is disabled for #{RUBY_VERSION} in the current environment")
end

### DUPLICATE DRIFT TASKS
begin
  require "kettle/drift"
  Kettle::Drift.install_tasks
rescue LoadError
  desc("(stub) kettle:drift:check is unavailable")
  task("kettle:drift:check") do
    warn("NOTE: kettle-drift isn't installed, or is disabled for #{RUBY_VERSION} in the current environment")
  end
  desc("(stub) kettle:drift:update is unavailable")
  task("kettle:drift:update") do
    warn("NOTE: kettle-drift isn't installed, or is disabled for #{RUBY_VERSION} in the current environment")
  end
  desc("(stub) kettle:drift:force_update is unavailable")
  task("kettle:drift:force_update") do
    warn("NOTE: kettle-drift isn't installed, or is disabled for #{RUBY_VERSION} in the current environment")
  end
  desc("(stub) kettle:drift is unavailable")
  task("kettle:drift" => "kettle:drift:update")
end

### TEMPLATING TASKS
# These tasks are installed for the `kettle-jem` executable. Run full templating
# through `kettle-jem install`; use `kettle-jem template --only PATH` only for
# scoped file updates. The executable prepares the environment and then
# delegates here when rake orchestration is needed.
kettle_jem_selftest_unavailable_note = nil
begin
  require "kettle/jem"
  if Kettle::Jem.respond_to?(:install_tasks)
    Kettle::Jem.install_tasks
  else
    kettle_jem_selftest_unavailable_note = "NOTE: kettle-jem #{Kettle::Jem::Version::VERSION} does not provide rake tasks in this environment"
  end
rescue LoadError
  kettle_jem_selftest_unavailable_note = "NOTE: kettle-jem isn't installed, or is disabled for #{RUBY_VERSION} in the current environment"
end

if kettle_jem_selftest_unavailable_note
  desc("(stub) kettle:jem:selftest is unavailable")
  task("kettle:jem:selftest") do
    warn(kettle_jem_selftest_unavailable_note)
  end
end

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

# kettle-jem:freeze
# App-specific Hanami, database, federation, and auth tasks retained across template refreshes.
# kettle-jem:unfreeze

require "hanami/rake_tasks"
require_relative "config/database"
require "sequel"

Sequel.extension(:migration)

namespace :db do
  def current_migration_version(db)
    return 0 unless db.table_exists?(:schema_info)

    row = db[:schema_info].first
    (row && row[:version].to_i) || 0
  end

  desc "Run database migrations"
  task :migrate do
    Them::Server::Database.migrate
    db = Them::Server::Database.db
    puts "Migrations complete. Current version: #{current_migration_version(db)}"
  end

  desc "Print current migration version"
  task :version do
    puts current_migration_version(Them::Server::Database.db)
  end

  desc "Rollback database by N steps (default 1). Usage: rake db:rollback[steps]"
  task :rollback, [:steps] do |_task, args|
    db = Them::Server::Database.db
    current = current_migration_version(db)
    steps = (args[:steps] || "1").to_i
    target = [current - steps, 0].max
    Sequel::Migrator.run(db, "config/db/migrate", target: target)
    puts "Rolled back #{steps} step(s). Now at version: #{current_migration_version(db)}"
  end

  desc "Seed the database from config/db/seeds.rb"
  task :seed do
    seed_path = File.join(__dir__, "config/db/seeds.rb")
    abort "No seeds file at #{seed_path}" unless File.exist?(seed_path)

    require seed_path
    puts "Seed complete."
  end

  desc "Reset the database (delete SQLite file, migrate, seed)"
  task :reset do
    db = Them::Server::Database.db
    db&.disconnect

    database_url = ENV["DATABASE_URL"].to_s.strip
    sqlite_file = if database_url.start_with?("sqlite://")
      database_url.delete_prefix("sqlite://")
    elsif database_url.start_with?("sqlite:")
      database_url.delete_prefix("sqlite:")
    end
    sqlite_file = ENV["THEM_SERVER_DB"].to_s.strip if sqlite_file.to_s.empty?
    sqlite_file = File.join(__dir__, "config", "db", "them_server.sqlite") if sqlite_file.to_s.empty?

    if sqlite_file != ":memory:" && File.exist?(sqlite_file)
      File.delete(sqlite_file)
      puts "Deleted #{sqlite_file}"
    else
      puts "No SQLite file to delete (using DATABASE_URL=#{database_url.inspect})"
    end

    Rake::Task["db:migrate"].invoke
    Rake::Task["db:seed"].invoke if File.exist?(File.join(__dir__, "config/db/seeds.rb"))
    puts "DB reset complete."
  end
end

namespace :federation do
  desc "List known servers"
  task :list_known do
    rows = Them::Server::Database.db[:known_servers].all
    if rows.empty?
      puts "No known servers"
    else
      rows.each do |row|
        puts "- #{row[:base_url]} subscribed=#{row[:subscribed]} last_seen=#{row[:last_seen_at]}"
      end
    end
  end

  desc "Seed a known server. Usage: rake federation:seed_known[base_url,public_key_b64]"
  task :seed_known, [:base_url, :public_key_b64] do |_task, args|
    base_url = args[:base_url].to_s.strip
    public_key = args[:public_key_b64].to_s.strip
    abort "base_url is required" if base_url.empty?
    abort "public_key_b64 is required" if public_key.empty?

    db = Them::Server::Database.db
    now = Time.now
    row = db[:known_servers].where(base_url: base_url).first
    if row
      db[:known_servers].where(id: row[:id]).update(public_key_b64: public_key, updated_at: now)
      puts "Updated known server: #{base_url}"
    else
      db[:known_servers].insert(
        base_url: base_url,
        public_key_b64: public_key,
        subscribed: false,
        created_at: now,
        updated_at: now
      )
      puts "Added known server: #{base_url}"
    end
  end

  desc "Announce to a remote server. Usage: rake federation:announce[to_base_url,my_base_url]"
  task :announce, [:to_base_url, :my_base_url] do |_task, args|
    require "them/server/federation_client"
    to_base = args[:to_base_url].to_s.strip
    my_base = args[:my_base_url].to_s.strip
    abort "to_base_url is required" if to_base.empty?

    Them::Server::FederationClient.new.announce(to_base_url: to_base, my_base_url: my_base)
    puts "Announce sent to #{to_base}"
  end

  desc "Subscribe to a remote server. Usage: rake federation:subscribe[to_base_url,my_base_url]"
  task :subscribe, [:to_base_url, :my_base_url] do |_task, args|
    require "them/server/federation_client"
    to_base = args[:to_base_url].to_s.strip
    my_base = args[:my_base_url].to_s.strip
    abort "to_base_url is required" if to_base.empty?

    Them::Server::FederationClient.new.subscribe(to_base_url: to_base, my_base_url: my_base)
    puts "Subscribe sent to #{to_base}"
  end

  desc "Broadcast a stubbed gem record to all subscribed peers. Usage: rake federation:broadcast_stub[name,version,scope_path]"
  task :broadcast_stub, [:name, :version, :scope_path] do |_task, args|
    require "tempfile"
    require "them/server/federation_broadcaster"

    name = (args[:name] || "demo").to_s
    version = (args[:version] || "0.1.0").to_s
    scope = args[:scope_path].to_s.split("/").reject(&:empty?)
    previous = ENV["FEDERATION_BROADCAST"]
    ENV["FEDERATION_BROADCAST"] = "1"

    Tempfile.create(["stub", ".gem"]) do |tmp|
      tmp.binmode
      tmp.write("stubbed gem bytes for federation demo")
      tmp.flush
      Them::Server::FederationBroadcaster.broadcast_gem(
        name: name,
        version: version,
        scope_path: scope,
        file_path: tmp.path
      )
      scope_label = scope.empty? ? "(root)" : scope.join("/")
      puts "Broadcasted stub gem #{name}-#{version} (scope: #{scope_label})"
    end
  ensure
    ENV["FEDERATION_BROADCAST"] = previous
  end
end

namespace :auth do
  desc "Create a Rodauth account and associated owner. Usage: rake auth:create_user[email,password,name]"
  task :create_user, [:email, :password, :name] do |_task, args|
    require "bcrypt"

    email = args[:email].to_s.strip
    password = args[:password].to_s
    name = args[:name].to_s.strip
    abort "email is required" if email.empty?
    abort "password is required" if password.empty?

    name = email if name.empty?
    db = Them::Server::Database.db
    now = Time.now
    existing = db[:accounts].where(email: email).first
    if existing
      puts "Account already exists: #{email}"
    else
      password_hash = BCrypt::Password.create(password)
      account_id = db[:accounts].insert(
        email: email,
        status_id: 1,
        password_hash: password_hash,
        created_at: now,
        updated_at: now
      )
      puts "Created account ##{account_id} for #{email}"
      if db.schema(:owners).map(&:first).include?(:account_id)
        db[:owners].insert(
          name: name,
          public_key: nil,
          api_key: nil,
          account_id: account_id,
          created_at: now,
          updated_at: now
        )
        puts "Created owner for account ##{account_id}"
      end
    end
  end
end

# kettle-jem:unfreeze
