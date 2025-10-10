# This seeds file should create the database records required to run the app.
#
# The code should be idempotent so that it can be executed at any time.
#
# To load the seeds, run `hanami db seed`. Seeds are also loaded as part of `hanami db prepare`.

# For example, if you have appropriate repos available:
#
#   category_repo = Hanami.app["repos.category_repo"]
#   category_repo.create(title: "General")
#
# Alternatively, you can use relations directly:
#
#   categories = Hanami.app["relations.categories"]
#   categories.insert(title: "General")

require_relative "../../config/database"
require "gem/server/crypto"

DB = Gem::Server::Database.db
now = Time.now

peers = [
  {base_url: "http://localhost:9292"},
  {base_url: "http://localhost:9393"},
]

peers.each do |peer|
  row = DB[:known_servers].where(base_url: peer[:base_url]).first
  attrs = {
    base_url: peer[:base_url],
    public_key_b64: Gem::Server::Crypto.public_key_b64,
    subscribed: false,
    last_seen_at: nil,
    created_at: now,
    updated_at: now,
  }
  if row
    DB[:known_servers].where(id: row[:id]).update(attrs.merge(created_at: row[:created_at]))
  else
    DB[:known_servers].insert(attrs)
  end
end
