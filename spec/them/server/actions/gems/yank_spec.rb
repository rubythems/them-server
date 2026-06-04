# frozen_string_literal: true

require "spec_helper"
require "rack/test"

RSpec.describe Them::Server::Actions::Gems::Yank do
  include Rack::Test::Methods

  def app
    Hanami.app
  end

  let(:db) { Them::Server::Database.db }
  let(:owner_api_key) { "test-api-key-456" }
  let!(:owner_id) do
    db[:owners].insert(
      name: "gem-owner",
      api_key: owner_api_key,
      created_at: Time.now,
      updated_at: Time.now,
    )
  end

  let!(:gem_id) do
    db[:gems].insert(
      name: "test-gem",
      version: "1.0.0",
      scope_id: nil,
      file_path: "gems/test-gem-1.0.0.gem",
      yanked: false,
      created_at: Time.now,
      updated_at: Time.now,
    )
  end

  before do
    db[:gem_owners].insert(
      gem_id: gem_id,
      owner_id: owner_id,
      created_at: Time.now,
    )
  end

  describe "DELETE /{scope-path}/{gem}/versions/{version}" do
    context "without authentication" do
      it "returns 401 without API key" do
        delete "/test-gem/versions/1.0.0"

        expect(last_response.status).to eq(401)
        expect(last_response.body).to eq("API key required")
      end

      it "returns 401 with invalid API key" do
        delete "/test-gem/versions/1.0.0", {}, {"HTTP_X_API_KEY" => "invalid-key"}

        expect(last_response.status).to eq(401)
        expect(last_response.body).to eq("Invalid API key")
      end
    end

    context "with valid authentication" do
      it "yanks the gem successfully" do
        delete "/test-gem/versions/1.0.0", {}, {"HTTP_X_API_KEY" => owner_api_key}

        expect(last_response.status).to eq(200)
        expect(last_response.body).to eq("Gem yanked")

        # Verify gem is marked as yanked
        gem = db[:gems].where(id: gem_id).first
        expect(gem[:yanked]).to eq(true)
      end

      it "returns 404 for non-existent gem" do
        delete "/nonexistent-gem/versions/1.0.0", {}, {"HTTP_X_API_KEY" => owner_api_key}

        expect(last_response.status).to eq(404)
        expect(last_response.body).to eq("Gem not found")
      end

      it "returns 404 for non-existent version" do
        delete "/test-gem/versions/2.0.0", {}, {"HTTP_X_API_KEY" => owner_api_key}

        expect(last_response.status).to eq(404)
        expect(last_response.body).to eq("Gem not found")
      end
    end

    context "authorization checks" do
      let(:unauthorized_api_key) { "unauthorized-key" }
      let!(:unauthorized_owner_id) do
        db[:owners].insert(
          name: "unauthorized-owner",
          api_key: unauthorized_api_key,
          created_at: Time.now,
          updated_at: Time.now,
        )
      end

      it "returns 403 when owner is not authorized for gem" do
        delete "/test-gem/versions/1.0.0", {}, {"HTTP_X_API_KEY" => unauthorized_api_key}

        expect(last_response.status).to eq(403)
        expect(last_response.body).to eq("Not authorized to yank this gem")
      end
    end

    context "with scoped gems" do
      let!(:scope_id) do
        db[:scopes].insert(
          name: "myorg",
          parent_id: nil,
          created_at: Time.now,
          updated_at: Time.now,
        )
      end

      let!(:scoped_gem_id) do
        db[:gems].insert(
          name: "scoped-gem",
          version: "1.0.0",
          scope_id: scope_id,
          file_path: "gems/scoped-gem-1.0.0.gem",
          yanked: false,
          created_at: Time.now,
          updated_at: Time.now,
        )
      end

      before do
        db[:gem_owners].insert(
          gem_id: scoped_gem_id,
          owner_id: owner_id,
          created_at: Time.now,
        )
      end

      it "yanks scoped gem successfully" do
        delete "/myorg/scoped-gem/versions/1.0.0", {}, {"HTTP_X_API_KEY" => owner_api_key}

        expect(last_response.status).to eq(200)

        gem = db[:gems].where(id: scoped_gem_id).first
        expect(gem[:yanked]).to eq(true)
      end
    end

    context "with nested scopes" do
      let!(:parent_scope_id) do
        db[:scopes].insert(
          name: "myorg",
          parent_id: nil,
          created_at: Time.now,
          updated_at: Time.now,
        )
      end

      let!(:child_scope_id) do
        db[:scopes].insert(
          name: "team",
          parent_id: parent_scope_id,
          created_at: Time.now,
          updated_at: Time.now,
        )
      end

      let!(:nested_gem_id) do
        db[:gems].insert(
          name: "nested-gem",
          version: "1.0.0",
          scope_id: child_scope_id,
          file_path: "gems/nested-gem-1.0.0.gem",
          yanked: false,
          created_at: Time.now,
          updated_at: Time.now,
        )
      end

      before do
        db[:gem_owners].insert(
          gem_id: nested_gem_id,
          owner_id: owner_id,
          created_at: Time.now,
        )
      end

      it "yanks nested scoped gem successfully" do
        delete "/myorg/team/nested-gem/versions/1.0.0", {}, {"HTTP_X_API_KEY" => owner_api_key}

        expect(last_response.status).to eq(200)

        gem = db[:gems].where(id: nested_gem_id).first
        expect(gem[:yanked]).to eq(true)
      end
    end
  end
end
