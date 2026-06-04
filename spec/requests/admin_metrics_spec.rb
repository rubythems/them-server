# frozen_string_literal: true

require_relative "../../config/database"

RSpec.describe "Admin Federation Metrics", type: :request do
  let(:db) { Them::Server::Database.db }

  it "returns counts and timestamps" do
    t = Time.now
    db[:known_servers].insert(base_url: "http://m1", public_key_b64: "K1", subscribed: true, last_seen_at: t, last_announced_at: t, created_at: t, updated_at: t)
    db[:known_servers].insert(base_url: "http://m2", public_key_b64: "K2", subscribed: false, created_at: t, updated_at: t)

    get "/admin/federation/metrics"
    expect(last_response.status).to eq(200)
    body = JSON.parse(last_response.body)
    expect(body["known_servers_total"]).to eq(2)
    expect(body["known_servers_subscribed"]).to eq(1)
    expect(body).to have_key("federated_gems_total")
  end
end
