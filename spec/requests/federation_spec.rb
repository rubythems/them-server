# frozen_string_literal: true

require "json"
require "ed25519"
require "gem/server/crypto"

RSpec.describe "Federation", type: :request do
  let(:remote_signing_key) { Ed25519::SigningKey.generate }
  let(:remote_verify_key) { remote_signing_key.verify_key }
  let(:remote_pub_b64) { Base64.strict_encode64(remote_verify_key.to_bytes) }
  let(:base_url) { "https://remote.example.test" }

  def sign_canonical(method:, path:, signed_at:, body_digest:)
    canonical = Gem::Server::Crypto.canonical_request_string(method: method, path: path, signed_at: signed_at, body_digest: body_digest)
    Base64.strict_encode64(remote_signing_key.sign(canonical))
  end

  it "accepts announce and stores known server, then subscribes" do
    # Announce
    signed_at = Time.now.to_i
    to_sign = [base_url, remote_pub_b64, signed_at.to_s].join("\n")
    body_digest = Gem::Server::Crypto.sha256_hex(to_sign)
    signature = sign_canonical(method: "POST", path: "/federation/announce", signed_at: signed_at, body_digest: body_digest)

    payload = {base_url: base_url, public_key_b64: remote_pub_b64, signed_at: signed_at}
    post "/federation/announce", JSON.generate(payload), {
      "CONTENT_TYPE" => "application/json",
      "HTTP_X_SIGNATURE" => signature,
    }
    expect(last_response.status).to eq(200)

    # Subscribe
    body = {base_url: base_url, signed_at: signed_at}
    body_str = JSON.generate(body)
    body_digest = Gem::Server::Crypto.sha256_hex(body_str)
    signature = sign_canonical(method: "POST", path: "/federation/subscribe", signed_at: signed_at, body_digest: body_digest)

    post "/federation/subscribe", body_str, {
      "CONTENT_TYPE" => "application/json",
      "HTTP_X_SIGNATURE" => signature,
    }
    expect(last_response.status).to eq(200)
  end

  it "accepts push for a federated gem and validates scope and gem" do
    # First, announce to register known server
    signed_at = Time.now.to_i
    to_sign = [base_url, remote_pub_b64, signed_at.to_s].join("\n")
    sig = sign_canonical(method: "POST", path: "/federation/announce", signed_at: signed_at, body_digest: Gem::Server::Crypto.sha256_hex(to_sign))
    post "/federation/announce", JSON.generate({base_url: base_url, public_key_b64: remote_pub_b64, signed_at: signed_at}), {
      "CONTENT_TYPE" => "application/json",
      "HTTP_X_SIGNATURE" => sig,
    }
    expect(last_response.status).to eq(200)

    # Push a gem record for scope foo
    name = "demo"
    version = "0.1.0"
    scope_path = ["foo"]
    digest_sha256 = "deadbeef"
    record_string = [name, version, scope_path.join("/"), digest_sha256].join("\n")
    record_sig_b64 = Base64.strict_encode64(remote_signing_key.sign(record_string))

    push_payload = {
      from_base_url: base_url,
      name: name,
      version: version,
      scope_path: scope_path,
      digest_sha256: digest_sha256,
      record_sig_b64: record_sig_b64,
      signed_at: signed_at,
    }
    body_str = JSON.generate(push_payload)
    body_digest = Gem::Server::Crypto.sha256_hex(body_str)
    signature = sign_canonical(method: "POST", path: "/federation/push", signed_at: signed_at, body_digest: body_digest)

    post "/federation/push", body_str, {
      "CONTENT_TYPE" => "application/json",
      "HTTP_X_SIGNATURE" => signature,
    }
    expect(last_response.status).to eq(202)

    # Validate scope
    get "/federation/validate/scope/foo"
    expect(last_response.status).to eq(200)
    scope_json = JSON.parse(last_response.body)
    expect(scope_json["exists"]).to eq(true)

    # Validate gem
    get "/federation/validate/gem/foo/demo"
    expect(last_response.status).to eq(200)
    gem_json = JSON.parse(last_response.body)
    expect(gem_json["exists"]).to eq(true)
    expect(gem_json["source"]).to eq("federated")
    expect(gem_json["name"]).to eq(name)
    expect(gem_json["version"]).to eq(version)
  end
end

