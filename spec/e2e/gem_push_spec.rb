# frozen_string_literal: true

require "spec_helper"
require "fileutils"
require "open3"
require "rack/test"
require "net/http"
require "zlib"

RSpec.describe "Gem push e2e", type: :e2e do
  gem_version = "0.1.0"
  api_key = "test-api-key-123"

  def wait_for_server(port:, host: "127.0.0.1", timeout: server_start_timeout)
    deadline = Time.now + timeout
    loop do
      Net::HTTP.start(host, port, open_timeout: 0.2, read_timeout: 0.2) do |http|
        http.get("/")
      end
      return true
    rescue
      break if Time.now > deadline

      sleep 0.2
    end
    false
  end

  def server_start_timeout
    (RUBY_ENGINE == "truffleruby") ? 45 : 10
  end

  def test_port
    # Use an appraisal/worker-specific port so concurrent local appraisal runs do not collide.
    appraisal_port_offset = Zlib.crc32(ENV["BUNDLE_GEMFILE"].to_s) % 1_000
    worker_port_offset = ENV["TEST_ENV_NUMBER"].to_i
    20_000 + appraisal_port_offset + worker_port_offset
  end

  def server_url
    "http://localhost:#{test_port}"
  end

  def tmp_dir
    File.expand_path("../../tmp/e2e_gem_#{Zlib.crc32(ENV["BUNDLE_GEMFILE"].to_s)}", __dir__)
  end

  def kill_existing_servers(port)
    system("pkill -9 -f 'rackup.*#{port}' 2>/dev/null || true")
    sleep 0.5
  end

  def clean_e2e_database(db, api_key)
    db.run("PRAGMA foreign_keys = OFF") if db.database_type == :sqlite
    db.transaction do
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

      db[:owners].insert(
        name: "test_owner",
        api_key: api_key,
        created_at: Time.now,
        updated_at: Time.now
      )
    end
  ensure
    db.run("PRAGMA foreign_keys = ON") if db&.database_type == :sqlite
  end

  def build_test_gem(work_dir, gem_name, gem_version)
    gemspec_path = File.join(work_dir, "#{gem_name}.gemspec")
    gem_file = File.join(work_dir, "#{gem_name}-#{gem_version}.gem")

    FileUtils.mkdir_p(File.join(work_dir, "lib"))
    File.write(gemspec_path, <<~GEMSPEC)
      Gem::Specification.new do |s|
        s.name        = "#{gem_name}"
        s.version     = "#{gem_version}"
        s.summary     = "E2E test gem"
        s.authors     = ["Test"]
        s.email       = "peter@railsbling.com"
        s.license     = "MIT"
        s.files       = ["lib/#{gem_name}.rb"]
        s.require_paths = ["lib"]
        s.homepage    = "http://example.com/#{gem_name}"
        s.required_ruby_version = ">= 3.2.0"
      end
    GEMSPEC
    File.write(File.join(work_dir, "lib", "#{gem_name}.rb"), "# E2E test gem code\n")

    stdout, stderr, status = Open3.capture3("gem", "build", gemspec_path, chdir: work_dir)
    unless status.success?
      warn "gem build failed:\nSTDOUT:\n#{stdout}\nSTDERR:\n#{stderr}"
    end
    expect(status.success?).to be true

    gem_file
  end

  before(:all) do
    FileUtils.rm_rf(tmp_dir)
    FileUtils.mkdir_p(tmp_dir)
    # Kill any existing servers before starting tests
    kill_existing_servers(test_port)

    # Set up test owner ONCE for all tests in this suite
    # This avoids database synchronization issues with the server process
    db = Them::Server::Database.db

    clean_e2e_database(db, api_key)

    # Force WAL checkpoint to ensure data is written
    db.run("PRAGMA wal_checkpoint(FULL)")
    db.disconnect

    # Give SQLite time to complete the write
    sleep 1
  end

  before do
    # Ensure no servers are running from previous tests
    kill_existing_servers(test_port)

    # Start test server - the owner is already in the database from before(:all)
    root = File.expand_path("../..", __dir__)
    env = {
      "HANAMI_ENV" => "test",
      "RACK_ENV" => "test",
      "TEST_ENV_NUMBER" => ENV["TEST_ENV_NUMBER"].to_s,
      "THEM_SERVER_GEMS_DIR" => File.join(tmp_dir, "server_gems")
    }

    # Capture server output for debugging
    @server_log = File.join(tmp_dir, "server.log")
    @server_err_log = File.join(tmp_dir, "server_err.log")

    @server_pid = Process.spawn(
      env, "bin/rackup", "-p", test_port.to_s,
      chdir: root,
      out: @server_log,
      err: @server_err_log
    )

    unless wait_for_server(port: test_port)
      warn "\n=== SERVER LOG ===\n#{File.read(@server_log)}" if File.exist?(@server_log)
      warn "\n=== SERVER ERROR LOG ===\n#{File.read(@server_err_log)}" if File.exist?(@server_err_log)
      raise "Server failed to start"
    end
  end

  after do
    if @server_pid
      begin
        Process.kill("TERM", @server_pid)
        sleep 0.2
        begin
          Process.kill("KILL", @server_pid)
        rescue
          nil
        end
      rescue
      ensure
        begin
          Process.wait(@server_pid)
        rescue
        end
      end
      @server_pid = nil
    end
    # Final cleanup to ensure the port is free
    kill_existing_servers(test_port)
  end

  after(:all) do
    FileUtils.rm_rf(tmp_dir)
    kill_existing_servers(test_port)
  end

  it "pushes a gem to the test server" do
    gem_name = "e2e_test_gem_curl"
    work_dir = File.join(tmp_dir, gem_name)

    FileUtils.mkdir_p(work_dir)
    gem_file = build_test_gem(work_dir, gem_name, gem_version)

    # Use curl to simulate gem push to /api/v1/gems with basic auth and binary data
    stdout, stderr, status = Open3.capture3(
      "curl",
      "-X",
      "POST",
      "-u",
      "#{api_key}:",
      "-H",
      "Content-Type: application/octet-stream",
      "--data-binary",
      "@#{gem_file}",
      "#{server_url}/api/v1/gems"
    )

    # Debug: print server logs if the test fails
    unless status.success? && stdout.include?("Successfully registered gem")
      warn "\n=== CURL FAILED ==="
      warn "STDOUT: #{stdout}"
      warn "STDERR: #{stderr}"
      if File.exist?(@server_log)
        warn "\n=== SERVER LOG ==="
        warn File.read(@server_log)
      end
      if File.exist?(@server_err_log)
        warn "\n=== SERVER ERROR LOG ==="
        warn File.read(@server_err_log)
      end
    end

    expect(status.success?).to be true
    expect(stdout).to include("Successfully registered gem")
  end

  it "pushes a gem using gem push command" do
    gem_name = "e2e_test_gem_push"
    work_dir = File.join(tmp_dir, gem_name)

    FileUtils.mkdir_p(work_dir)
    gem_file = build_test_gem(work_dir, gem_name, gem_version)

    # Set up .gemrc for gem push with custom source
    File.write(File.join(work_dir, ".gemrc"), "---\n:rubygems_api_key: #{api_key}\n")

    # Use gem push
    stdout, stderr, status = Open3.capture3(
      {"RUBYGEMS_HOST" => server_url, "HOME" => work_dir},
      "gem",
      "push",
      gem_file,
      chdir: work_dir
    )
    unless status.success?
      warn "gem push failed:\nSTDOUT:\n#{stdout}\nSTDERR:\n#{stderr}"
      if File.exist?(@server_log)
        warn "\n=== SERVER LOG ==="
        warn File.read(@server_log)
      end
      if File.exist?(@server_err_log)
        warn "\n=== SERVER ERROR LOG ==="
        warn File.read(@server_err_log)
      end
    end
    expect(status.success?).to be true
    expect(stdout).to include("Successfully registered gem")
  end
end
