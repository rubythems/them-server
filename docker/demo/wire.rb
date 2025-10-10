# frozen_string_literal: true

require "gem/server/federation_client"
require "net/http"

# Wait for servers to boot
sleep(Integer(ENV.fetch("WIRE_WAIT", 3)))

client = Gem::Server::FederationClient.new

# server1 -> server2
ENV["FEDERATION_BASE_URL"] = "http://server1:9292"
client.announce(to_base_url: "http://server2:9393")
client.subscribe(to_base_url: "http://server2:9393")

# server2 -> server1
ENV["FEDERATION_BASE_URL"] = "http://server2:9393"
client.announce(to_base_url: "http://server1:9292")
client.subscribe(to_base_url: "http://server1:9292")

# Optional: curl admin known servers to show state
begin
  puts "-- server1 known_servers --"
  puts Net::HTTP.get(URI("http://server1:9292/admin/known_servers"))
  puts "-- server2 known_servers --"
  puts Net::HTTP.get(URI("http://server2:9393/admin/known_servers"))
rescue => e
  warn "wire: curl failed: #{e.class}: #{e.message}"
end

