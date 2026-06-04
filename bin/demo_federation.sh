#!/usr/bin/env bash
set -euo pipefail

# Minimal demo: run two local servers with separate DBs and ports, and wire them with federation announce+subscribe.
# Requirements: bash, bundler, Ruby; ports 9292 and 9393 free.

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

# Ensure deps
bundle check >/dev/null 2>&1 || bundle install

# Prepare server 1
export THEM_SERVER_DB="$ROOT_DIR/config/db/them_server_1.db"
bundle exec rake db:reset
export FEDERATION_BASE_URL="http://localhost:9292"
# Seed known servers in server 1 DB
bundle exec rake db:seed

# Start server 1
HANAMI_PORT=9292 HANAMI_ENV=development THEM_SERVER_DB="$THEM_SERVER_DB" \
  bundle exec rackup -p 9292 -E development --host 0.0.0.0 --daemonize

echo "Server 1 running on http://localhost:9292 using DB $THEM_SERVER_DB"

# Prepare server 2
export THEM_SERVER_DB="$ROOT_DIR/config/db/them_server_2.db"
bundle exec rake db:reset
export FEDERATION_BASE_URL="http://localhost:9393"
# Seed known servers in server 2 DB
bundle exec rake db:seed

# Start server 2
HANAMI_PORT=9393 HANAMI_ENV=development THEM_SERVER_DB="$THEM_SERVER_DB" \
  bundle exec rackup -p 9393 -E development --host 0.0.0.0 --daemonize

echo "Server 2 running on http://localhost:9393 using DB $THEM_SERVER_DB"

# Give servers a second to boot
sleep 2

# Announce 1 -> 2 and subscribe 2 to 1
export FEDERATION_BASE_URL="http://localhost:9292"
ruby -e 'require "them/server/federation_client"; Them::Server::FederationClient.new.announce(to_base_url: "http://localhost:9393")'
ruby -e 'require "them/server/federation_client"; Them::Server::FederationClient.new.subscribe(to_base_url: "http://localhost:9393")'

# Announce 2 -> 1 and subscribe 1 to 2
export FEDERATION_BASE_URL="http://localhost:9393"
ruby -e 'require "them/server/federation_client"; Them::Server::FederationClient.new.announce(to_base_url: "http://localhost:9292")'
ruby -e 'require "them/server/federation_client"; Them::Server::FederationClient.new.subscribe(to_base_url: "http://localhost:9292")'

echo "Federation demo complete. Try hitting /admin/known_servers on each server."
echo "  curl http://localhost:9292/admin/known_servers"
echo "  curl http://localhost:9393/admin/known_servers"
