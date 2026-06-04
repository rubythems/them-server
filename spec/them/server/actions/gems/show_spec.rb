# frozen_string_literal: true

require "spec_helper"
require "rack/test"

RSpec.describe Them::Server::Actions::Gems::Show do
  include Rack::Test::Methods

  def app
    Hanami.app
  end

  let(:db) { Them::Server::Database.db }

  describe "GET /" do
    context "with no gems" do
      it "returns empty JSON array" do
        get "/"

        expect(last_response.status).to eq(200)
        expect(last_response.content_type).to include("application/json")
        expect(JSON.parse(last_response.body)).to eq([])
      end
    end

    context "with gems in root scope" do
      before do
        db[:gems].insert(
          name: "test-gem",
          version: "1.0.0",
          scope_id: nil,
          file_path: "gems/test-gem-1.0.0.gem",
          yanked: false,
          created_at: Time.now,
          updated_at: Time.now,
        )
        db[:gems].insert(
          name: "another-gem",
          version: "2.0.0",
          scope_id: nil,
          file_path: "gems/another-gem-2.0.0.gem",
          yanked: false,
          created_at: Time.now,
          updated_at: Time.now,
        )
      end

      it "lists all non-yanked gems" do
        get "/"

        expect(last_response.status).to eq(200)
        gems = JSON.parse(last_response.body)
        expect(gems.length).to eq(2)
        expect(gems.map { |g| g["name"] }).to include("test-gem", "another-gem")
      end
    end

    context "with yanked gems" do
      before do
        db[:gems].insert(
          name: "visible-gem",
          version: "1.0.0",
          scope_id: nil,
          file_path: "gems/visible-gem-1.0.0.gem",
          yanked: false,
          created_at: Time.now,
          updated_at: Time.now,
        )
        db[:gems].insert(
          name: "yanked-gem",
          version: "1.0.0",
          scope_id: nil,
          file_path: "gems/yanked-gem-1.0.0.gem",
          yanked: true,
          created_at: Time.now,
          updated_at: Time.now,
        )
      end

      it "excludes yanked gems from listing" do
        get "/"

        gems = JSON.parse(last_response.body)
        expect(gems.length).to eq(1)
        expect(gems.first["name"]).to eq("visible-gem")
      end
    end
  end

  describe "GET /{scope-path}" do
    context "with scoped gems" do
      let!(:scope_id) do
        db[:scopes].insert(
          name: "myorg",
          parent_id: nil,
          created_at: Time.now,
          updated_at: Time.now,
        )
      end

      before do
        db[:gems].insert(
          name: "scoped-gem",
          version: "1.0.0",
          scope_id: scope_id,
          file_path: "gems/scoped-gem-1.0.0.gem",
          yanked: false,
          created_at: Time.now,
          updated_at: Time.now,
        )
        # Add a root gem to ensure scoping works
        db[:gems].insert(
          name: "root-gem",
          version: "1.0.0",
          scope_id: nil,
          file_path: "gems/root-gem-1.0.0.gem",
          yanked: false,
          created_at: Time.now,
          updated_at: Time.now,
        )
      end

      it "lists only gems in the specified scope" do
        get "/myorg"

        expect(last_response.status).to eq(200)
        gems = JSON.parse(last_response.body)
        expect(gems.length).to eq(1)
        expect(gems.first["name"]).to eq("scoped-gem")
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

      it "lists gems in nested scope" do
        get "/myorg/team"

        expect(last_response.status).to eq(200)
        gems = JSON.parse(last_response.body)
        expect(gems.length).to eq(1)
        expect(gems.first["name"]).to eq("nested-gem")
      end
    end
  end

  describe "GET /{scope-path}/{gem}" do
    let(:gem_content) { "fake gem file content" }
    let(:gem_file_path) { "gems/test-gem-1.0.0.gem" }

    before do
      FileUtils.mkdir_p("gems")
      File.write(gem_file_path, gem_content)

      db[:gems].insert(
        name: "test-gem",
        version: "1.0.0",
        scope_id: nil,
        file_path: gem_file_path,
        yanked: false,
        created_at: Time.now,
        updated_at: Time.now,
      )
    end

    after do
      FileUtils.rm_f(gem_file_path)
    end

    it "returns the gem file" do
      get "/test-gem"

      expect(last_response.status).to eq(200)
      expect(last_response.content_type).to eq("application/octet-stream")
      expect(last_response.headers["Content-Disposition"]).to include("test-gem-1.0.0.gem")
      expect(last_response.body).to eq(gem_content)
    end

    it "returns 404 for non-existent gem" do
      get "/nonexistent-gem"

      expect(last_response.status).to eq(404)
      expect(last_response.body).to eq("Gem not found")
    end

    it "returns 404 for yanked gem" do
      db[:gems].where(name: "test-gem").update(yanked: true)

      get "/test-gem"

      expect(last_response.status).to eq(404)
    end

    context "with multiple versions" do
      before do
        newer_file_path = "gems/test-gem-2.0.0.gem"
        File.write(newer_file_path, "newer version content")

        db[:gems].insert(
          name: "test-gem",
          version: "2.0.0",
          scope_id: nil,
          file_path: newer_file_path,
          yanked: false,
          created_at: Time.now,
          updated_at: Time.now,
        )
      end

      after do
        FileUtils.rm_f("gems/test-gem-2.0.0.gem")
      end

      it "returns the latest version" do
        get "/test-gem"

        expect(last_response.status).to eq(200)
        expect(last_response.headers["Content-Disposition"]).to include("test-gem-2.0.0.gem")
        expect(last_response.body).to eq("newer version content")
      end
    end
  end
end
