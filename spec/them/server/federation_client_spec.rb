# frozen_string_literal: true

require "webmock/rspec"
require "json"
require "them/server/federation_client"

RSpec.describe Them::Server::FederationClient do
  before { ENV["FEDERATION_BASE_URL"] = "http://me.local" }
  after { ENV.delete("FEDERATION_BASE_URL") }

  let(:client) { described_class.new }

  it "announces to a remote peer with signature" do
    stub = stub_request(:post, "http://peer.test/federation/announce")
      .with { |req| req.headers.key?("X-Signature") && JSON.parse(req.body).fetch("base_url") == "http://me.local" }
      .to_return(status: 200, body: {status: "ok"}.to_json)

    client.announce(to_base_url: "http://peer.test")
    expect(stub).to have_been_requested
  end

  it "subscribes to a remote peer with signature" do
    stub = stub_request(:post, "http://peer.test/federation/subscribe")
      .with { |req| req.headers.key?("X-Signature") && JSON.parse(req.body).fetch("base_url") == "http://me.local" }
      .to_return(status: 200, body: {status: "ok"}.to_json)

    client.subscribe(to_base_url: "http://peer.test")
    expect(stub).to have_been_requested
  end
end
