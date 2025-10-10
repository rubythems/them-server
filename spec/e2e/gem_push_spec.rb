# frozen_string_literal: true

require "spec_helper"
require "fileutils"
require "open3"
require "rack/test"
require "net/http"

RSpec.describe "Gem push e2e", type: :e2e do
  tmp_dir = File.expand_path("../../tmp/e2e_gem", __dir__)
  gem_version = "0.1.0"
  api_key = "test-api-key-123"
  # Use a different port to avoid conflicts with dev server (9292) and docker federation (9292, 9393)
  test_port = 9494
  server_url = "http://localhost:#{test_port}"

  def wait_for_server(host: "127.0.0.1", port: 9494, timeout: 10)
    deadline = Time.now + timeout
    loop do
      Net::HTTP.start(host, port, open_timeout: 0.2, read_timeout: 0.2) do |http|
        http.get("/")
      end
      return true
    rescue StandardError
      break if Time.now > deadline

      sleep 0.2
    end
    false
  end

  def kill_existing_servers
    # Kill any existing e2e test servers on port 9494
    system("pkill -9 -f 'rackup.*9494' 2>/dev/null || true")
    sleep 0.5
  end

  before(:all) do
    FileUtils.rm_rf(tmp_dir)
    FileUtils.mkdir_p(tmp_dir)
    # Kill any existing servers before starting tests
    kill_existing_servers

    # Set up test owner ONCE for all tests in this suite
    # This avoids database synchronization issues with the server process
    db = Gem::Server::Database.db

    # Clear database in proper order to avoid foreign key constraint violations
    db.transaction do
      db[:gem_owners].delete
      db[:scope_owners].delete
      db[:gems].delete
      db[:scopes].delete
      db[:owners].delete

      # Insert the test owner
      db[:owners].insert(
        name: "test_owner",
        api_key: api_key,
        created_at: Time.now,
        updated_at: Time.now,
      )
    end

    # Force WAL checkpoint to ensure data is written
    db.run("PRAGMA wal_checkpoint(FULL)")
    db.disconnect

    # Give SQLite time to complete the write
    sleep 1
  end

  before(:each) do
    # Ensure no servers are running from previous tests
    kill_existing_servers

    # Start test server - the owner is already in the database from before(:all)
    root = File.expand_path("../..", __dir__)
    env = {
      "HANAMI_ENV" => "test",
      "RACK_ENV" => "test",
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

    raise "Server failed to start" unless wait_for_server(port: test_port)
  end

  after(:each) do
    if @server_pid
      begin
        Process.kill("TERM", @server_pid)
        sleep 0.2
        Process.kill("KILL", @server_pid) rescue nil
      rescue StandardError
      ensure
        begin
          Process.wait(@server_pid)
        rescue StandardError
        end
      end
      @server_pid = nil
    end
    # Final cleanup to ensure the port is free
    kill_existing_servers
  end

  after(:all) do
    FileUtils.rm_rf(tmp_dir)
    kill_existing_servers
  end

  it "pushes a gem to the test server" do
    gem_name = "e2e_test_gem_curl"
    gem_file = File.join(tmp_dir, "#{gem_name}-#{gem_version}.gem")

    Dir.chdir(tmp_dir) do
      # Create a minimal gemspec
      File.write("#{gem_name}.gemspec", <<~GEMSPEC)
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
      FileUtils.mkdir_p("lib")
      File.write("lib/#{gem_name}.rb", "# E2E test gem code\n")
      # Build the gem
      system("gem build #{gem_name}.gemspec")

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
        "#{server_url}/api/v1/gems",
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
  end

  it "pushes a gem using gem push command" do

    gem_name = "e2e_test_gem_push"
    gem_file = File.join(tmp_dir, "#{gem_name}-#{gem_version}.gem")

    Dir.chdir(tmp_dir) do
      # Create a minimal gemspec
      File.write("#{gem_name}.gemspec", <<~GEMSPEC)
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
      FileUtils.mkdir_p("lib")
      File.write("lib/#{gem_name}.rb", "# E2E test gem code\n")
      # Build the gem
      system("gem build #{gem_name}.gemspec")

      # Set up .gemrc for gem push with custom source
      File.write(".gemrc", "---\n:rubygems_api_key: #{api_key}\n")
      ENV["RUBYGEMS_HOST"] = server_url
      ENV["HOME"] = tmp_dir

      # Use gem push
      stdout, stderr, status = Open3.capture3("gem push #{gem_file}")
      unless status.success?
        warn "gem push failed:\nSTDOUT:\n#{stdout}\nSTDERR:\n#{stderr}"
      end
      expect(status.success?).to be true
      expect(stdout).to include("Successfully registered gem")
    end
  end
end
