# frozen_string_literal: true

require "json"
require_relative "../../config/database"

RSpec.describe "Admin Known Servers", type: :request do
  let(:db) { Them::Server::Database.db }

  it "lists known servers" do
    db[:known_servers].insert(
      base_url: "http://example.test",
      public_key_b64: "PUB",
      subscribed: false,
      created_at: Time.now,
      updated_at: Time.now
    )

    get "/admin/known_servers"
    expect(last_response.status).to eq(200)
    body = JSON.parse(last_response.body)
    expect(body).to be_a(Array)
    expect(body.first["base_url"]).to eq("http://example.test")
  end

  it "toggles subscribed flag" do
    db[:known_servers].insert(
      base_url: "http://toggle.test",
      public_key_b64: "PUB",
      subscribed: false,
      created_at: Time.now,
      updated_at: Time.now
    )

    post "/admin/known_servers/toggle", JSON.generate({base_url: "http://toggle.test", subscribed: true}), {"CONTENT_TYPE" => "application/json"}
    expect(last_response.status).to eq(200)
    expect(JSON.parse(last_response.body)).to include("base_url" => "http://toggle.test", "subscribed" => true)
    row = db[:known_servers].where(base_url: "http://toggle.test").first
    expect(row[:subscribed]).to eq(true)
  end
end
