# frozen_string_literal: true

require "spec_helper"
require "rack/test"

RSpec.describe Them::Server::Actions::Gems::Create do
  include Rack::Test::Methods

  def app
    Hanami.app
  end

  let(:db) { Them::Server::Database.db }
  let(:owner_api_key) { "test-api-key-123" }
  let!(:owner_id) do
    db[:owners].insert(
      name: "test-owner",
      api_key: owner_api_key,
      created_at: Time.now,
      updated_at: Time.now,
    )
  end

  describe "POST /{scope-path}" do
    let(:gem_spec) { double("Gem::Specification", name: "test-gem", version: "1.0.0") }
    let(:gem_package) { double("Gem::Package", spec: gem_spec) }

    before do
      allow(Gem::Package).to receive(:new).and_return(gem_package)
      FileUtils.mkdir_p("gems")
    end

    after do
      FileUtils.rm_rf("gems")
    end

    context "without authentication" do
      it "returns 401 without API key" do
        file = Rack::Test::UploadedFile.new(StringIO.new("fake gem"), "application/octet-stream", original_filename: "test.gem")
        post "/", file: file

        expect(last_response.status).to eq(401)
        expect(last_response.body).to eq("API key required")
      end

      it "returns 401 with invalid API key" do
        file = Rack::Test::UploadedFile.new(StringIO.new("fake gem"), "application/octet-stream", original_filename: "test.gem")
        post "/", {file: file}, {"HTTP_X_API_KEY" => "invalid-key"}

        expect(last_response.status).to eq(401)
        expect(last_response.body).to eq("Invalid API key")
      end
    end

    context "without file" do
      it "returns 400" do
        post "/", {}, {"HTTP_X_API_KEY" => owner_api_key}

        expect(last_response.status).to eq(400)
        expect(last_response.body).to eq("No gem file provided")
      end
    end

    context "to root scope" do
      it "pushes gem successfully" do
        file = Rack::Test::UploadedFile.new(StringIO.new("fake gem content"), "application/octet-stream", original_filename: "test-gem.gem")

        post "/", {file: file}, {"HTTP_X_API_KEY" => owner_api_key}

        expect(last_response.status).to eq(201)
        expect(last_response.body).to eq("Successfully registered gem: test-gem (1.0.0)")

        # Verify database
        gem = db[:gems].where(name: "test-gem", version: "1.0.0").first
        expect(gem).not_to be_nil
        expect(gem[:scope_id]).to be_nil
        expect(gem[:yanked]).to eq(false)

        # Verify owner association
        gem_owner = db[:gem_owners].where(gem_id: gem[:id], owner_id: owner_id).first
        expect(gem_owner).not_to be_nil
      end
    end

    context "to scoped namespace" do
      let!(:scope_id) do
        db[:scopes].insert(
          name: "myorg",
          parent_id: nil,
          created_at: Time.now,
          updated_at: Time.now,
        )
      end

      before do
        db[:scope_owners].insert(
          scope_id: scope_id,
          owner_id: owner_id,
          created_at: Time.now,
        )
      end

      it "pushes gem to scope successfully" do
        file = Rack::Test::UploadedFile.new(StringIO.new("fake gem content"), "application/octet-stream", original_filename: "test-gem.gem")

        post "/myorg", {file: file}, {"HTTP_X_API_KEY" => owner_api_key}

        expect(last_response.status).to eq(201)

        # Verify database
        gem = db[:gems].where(name: "test-gem", version: "1.0.0").first
        expect(gem).not_to be_nil
        expect(gem[:scope_id]).to eq(scope_id)
      end
    end

    context "authorization checks" do
      let!(:scope_id) do
        db[:scopes].insert(
          name: "restricted-org",
          parent_id: nil,
          created_at: Time.now,
          updated_at: Time.now,
        )
      end

      it "returns 403 when owner is not authorized for scope" do
        file = Rack::Test::UploadedFile.new(StringIO.new("fake gem content"), "application/octet-stream", original_filename: "test-gem.gem")

        post "/restricted-org", {file: file}, {"HTTP_X_API_KEY" => owner_api_key}

        expect(last_response.status).to eq(403)
        expect(last_response.body).to eq("Not authorized to push to this scope")
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

      before do
        db[:scope_owners].insert(
          scope_id: child_scope_id,
          owner_id: owner_id,
          created_at: Time.now,
        )
      end

      it "pushes gem to nested scope" do
        file = Rack::Test::UploadedFile.new(StringIO.new("fake gem content"), "application/octet-stream", original_filename: "test-gem.gem")

        post "/myorg/team", {file: file}, {"HTTP_X_API_KEY" => owner_api_key}

        expect(last_response.status).to eq(201)

        gem = db[:gems].where(name: "test-gem").first
        expect(gem[:scope_id]).to eq(child_scope_id)
      end
    end

    context "raw octet-stream upload" do
      it "accepts POST /api/v1/gems with raw body and Authorization header" do
        body = "FAKEGEMBYTES".b
        headers = {
          "CONTENT_TYPE" => "application/octet-stream",
          "HTTP_AUTHORIZATION" => "RubyGems #{owner_api_key}",
        }

        post "/api/v1/gems", body, headers

        expect(last_response.status).to eq(201)
        expect(last_response.body).to eq("Successfully registered gem: test-gem (1.0.0)")

        gem = db[:gems].where(name: "test-gem", version: "1.0.0").first
        expect(gem).not_to be_nil
        expect(gem[:scope_id]).to be_nil
      end
    end
  end
end
