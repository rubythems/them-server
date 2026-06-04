# frozen_string_literal: true

require "spec_helper"
require "them/server/oauth2_config"
require "them/server/authenticator"

RSpec.describe "OAuth2 Integration" do
  before do
    # Clear cached client between tests
    Them::Server::OAuth2Config.instance_variable_set(:@client, nil)
  end

  describe Them::Server::OAuth2Config do
    describe ".enabled?" do
      it "returns false when OAUTH2_PROVIDER_URL is not set" do
        allow(ENV).to receive(:[]).with("OAUTH2_PROVIDER_URL").and_return(nil)
        expect(described_class.enabled?).to be false
      end

      it "returns true when OAUTH2_PROVIDER_URL is set" do
        allow(ENV).to receive(:[]).with("OAUTH2_PROVIDER_URL").and_return("https://github.com")
        expect(described_class.enabled?).to be true
      end
    end

    describe ".client" do
      it "returns nil when not configured" do
        allow(ENV).to receive(:[]).with("OAUTH2_PROVIDER_URL").and_return(nil)
        expect(described_class.client).to be_nil
      end

      it "creates a client when properly configured" do
        allow(ENV).to receive(:[]).with("OAUTH2_PROVIDER_URL").and_return("https://github.com")
        allow(ENV).to receive(:[]).with("OAUTH2_CLIENT_ID").and_return("test-client-id")
        allow(ENV).to receive(:[]).with("OAUTH2_CLIENT_SECRET").and_return("test-secret")
        allow(ENV).to receive(:[]).with("OAUTH2_TOKEN_URL").and_return(nil)
        allow(ENV).to receive(:[]).with("OAUTH2_AUTHORIZE_URL").and_return(nil)

        client = described_class.client
        expect(client).to be_a(OAuth2::Client)
        expect(client.id).to eq("test-client-id")
        expect(client.secret).to eq("test-secret")
      end

      it "caches the client instance" do
        allow(ENV).to receive(:[]).with("OAUTH2_PROVIDER_URL").and_return("https://github.com")
        allow(ENV).to receive(:[]).with("OAUTH2_CLIENT_ID").and_return("test-client-id")
        allow(ENV).to receive(:[]).with("OAUTH2_CLIENT_SECRET").and_return("test-secret")
        allow(ENV).to receive(:[]).with("OAUTH2_TOKEN_URL").and_return(nil)
        allow(ENV).to receive(:[]).with("OAUTH2_AUTHORIZE_URL").and_return(nil)

        client1 = described_class.client
        client2 = described_class.client
        expect(client1).to be(client2)
      end
    end

    describe ".validate_token", :vcr do
      context "when OAuth2 is not configured" do
        before do
          allow(ENV).to receive(:[]).with("OAUTH2_PROVIDER_URL").and_return(nil)
        end

        it "returns nil" do
          result = described_class.validate_token("some-token")
          expect(result).to be_nil
        end
      end

      context "when token is empty" do
        it "returns nil" do
          result = described_class.validate_token("")
          expect(result).to be_nil
        end

        it "returns nil for nil token" do
          result = described_class.validate_token(nil)
          expect(result).to be_nil
        end
      end
    end
  end

  describe Them::Server::Authenticator do
    describe ".authenticate" do
      let(:env) { {} }

      context "with OAuth2 Bearer token" do
        before do
          allow(Them::Server::OAuth2Config).to receive(:enabled?).and_return(true)
          allow(Them::Server::OAuth2Config).to receive(:validate_token).and_return(token_info)
        end

        let(:token_info) do
          {
            "active" => true,
            "username" => "octocat",
            "scope" => "read write",
            "client_id" => "test-client",
          }
        end

        it "authenticates valid Bearer tokens" do
          env["HTTP_AUTHORIZATION"] = "Bearer valid-token-123"

          result = described_class.authenticate(env)

          expect(result[:authenticated]).to be true
          expect(result[:scheme]).to eq(:oauth2)
          expect(result[:user]).to eq("octocat")
          expect(result[:token]).to eq("valid-token-123")
          expect(result[:scopes]).to eq(["read", "write"])
          expect(result[:token_info]).to eq(token_info)
        end

        it "handles tokens without scopes" do
          allow(Them::Server::OAuth2Config).to receive(:validate_token).and_return(
            {"active" => true, "username" => "user"}
          )
          env["HTTP_AUTHORIZATION"] = "Bearer token-no-scopes"

          result = described_class.authenticate(env)

          expect(result[:authenticated]).to be true
          expect(result[:scopes]).to eq([])
        end

        it "rejects inactive tokens" do
          allow(Them::Server::OAuth2Config).to receive(:validate_token).and_return(
            {"active" => false}
          )
          env["HTTP_AUTHORIZATION"] = "Bearer inactive-token"

          result = described_class.authenticate(env)

          expect(result[:authenticated]).to be false
        end

        it "rejects invalid tokens" do
          allow(Them::Server::OAuth2Config).to receive(:validate_token).and_return(nil)
          env["HTTP_AUTHORIZATION"] = "Bearer invalid-token"

          result = described_class.authenticate(env)

          expect(result[:authenticated]).to be false
        end

        it "fails when OAuth2 token is invalid, even with other credentials present" do
          allow(Them::Server::OAuth2Config).to receive(:validate_token).and_return(nil)
          env["HTTP_AUTHORIZATION"] = "Bearer invalid-oauth-token"
          env["HTTP_X_API_KEY"] = "fallback-api-key"

          result = described_class.authenticate(env)

          expect(result[:authenticated]).to be false
          expect(result[:scheme]).to eq(:oauth2)
        end
      end

      context "with RubyGems API key header" do
        it "authenticates via X-Rubygems-Api-Key" do
          env["HTTP_X_RUBYGEMS_API_KEY"] = "rubygems-key-123"

          result = described_class.authenticate(env)

          expect(result[:authenticated]).to be true
          expect(result[:scheme]).to eq(:rubygems)
          expect(result[:user]).to eq("rubygems-key-123")
          expect(result[:token]).to eq("rubygems-key-123")
        end
      end

      context "with custom API key header" do
        it "authenticates via X-Api-Key" do
          env["HTTP_X_API_KEY"] = "custom-key-456"

          result = described_class.authenticate(env)

          expect(result[:authenticated]).to be true
          expect(result[:scheme]).to eq(:api_key)
          expect(result[:token]).to eq("custom-key-456")
        end
      end

      context "with HTTP Basic authentication" do
        it "authenticates using username from Basic auth" do
          credentials = Base64.strict_encode64("myapikey:password")
          env["HTTP_AUTHORIZATION"] = "Basic #{credentials}"

          result = described_class.authenticate(env)

          expect(result[:authenticated]).to be true
          expect(result[:scheme]).to eq(:basic)
          expect(result[:user]).to eq("myapikey")
          expect(result[:token]).to eq("myapikey")
        end

        it "handles Basic auth without password" do
          credentials = Base64.strict_encode64("myapikey")
          env["HTTP_AUTHORIZATION"] = "Basic #{credentials}"

          result = described_class.authenticate(env)

          expect(result[:authenticated]).to be true
          expect(result[:user]).to eq("myapikey")
        end

        it "handles invalid Base64 gracefully" do
          env["HTTP_AUTHORIZATION"] = "Basic !!invalid!!"

          result = described_class.authenticate(env)

          expect(result[:authenticated]).to be false
        end
      end

      context "with RubyGems Authorization scheme" do
        it "authenticates via Authorization: RubyGems" do
          env["HTTP_AUTHORIZATION"] = "RubyGems my-rubygems-key"

          result = described_class.authenticate(env)

          expect(result[:authenticated]).to be true
          expect(result[:scheme]).to eq(:rubygems)
          expect(result[:token]).to eq("my-rubygems-key")
        end
      end

      context "with raw Authorization header" do
        it "treats raw values as API keys" do
          env["HTTP_AUTHORIZATION"] = "raw-api-key-without-scheme"

          result = described_class.authenticate(env)

          expect(result[:authenticated]).to be true
          expect(result[:scheme]).to eq(:raw)
          expect(result[:token]).to eq("raw-api-key-without-scheme")
        end

        it "ignores values with unknown schemes" do
          env["HTTP_AUTHORIZATION"] = "UnknownScheme some-value"

          result = described_class.authenticate(env)

          expect(result[:authenticated]).to be false
        end
      end

      context "with no authentication" do
        it "returns unsuccessful result" do
          result = described_class.authenticate(env)

          expect(result[:authenticated]).to be false
          expect(result[:scheme]).to be_nil
          expect(result[:user]).to be_nil
          expect(result[:token]).to be_nil
          expect(result[:scopes]).to eq([])
        end
      end

      context "with multiple authentication methods" do
        before do
          allow(Them::Server::OAuth2Config).to receive(:enabled?).and_return(true)
          allow(Them::Server::OAuth2Config).to receive(:validate_token).and_return(
            {"active" => true, "username" => "oauth-user"}
          )
        end

        it "prefers OAuth2 Bearer over API keys" do
          env["HTTP_AUTHORIZATION"] = "Bearer oauth-token"
          env["HTTP_X_API_KEY"] = "api-key"

          result = described_class.authenticate(env)

          expect(result[:scheme]).to eq(:oauth2)
          expect(result[:user]).to eq("oauth-user")
        end

        it "falls back to API keys when OAuth2 token is invalid" do
          allow(Them::Server::OAuth2Config).to receive(:validate_token).and_return(nil)
          env["HTTP_AUTHORIZATION"] = "Bearer invalid-oauth-token"
          env["HTTP_X_API_KEY"] = "fallback-api-key"

          result = described_class.authenticate(env)

          expect(result[:authenticated]).to be false
          expect(result[:scheme]).to eq(:oauth2)
        end
      end
    end

    describe ".extract_api_key" do
      it "returns token from successful authentication" do
        env = {"HTTP_X_API_KEY" => "test-key"}
        key = described_class.extract_api_key(env)
        expect(key).to eq("test-key")
      end

      it "returns nil for failed authentication" do
        key = described_class.extract_api_key({})
        expect(key).to be_nil
      end
    end
  end
end
