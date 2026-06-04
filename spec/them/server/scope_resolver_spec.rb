# frozen_string_literal: true

require "spec_helper"
require "them/server/scope_resolver"

RSpec.describe Them::Server::ScopeResolver do
  let(:db) { Them::Server::Database.db }

  describe "#initialize" do
    it "accepts an array of path parts" do
      resolver = described_class.new(["org", "team", "gem"])
      expect(resolver.path_parts).to eq(["org", "team", "gem"])
    end

    it "compacts nil values" do
      resolver = described_class.new(["org", nil, "gem"])
      expect(resolver.path_parts).to eq(["org", "gem"])
    end

    it "handles empty array" do
      resolver = described_class.new([])
      expect(resolver.path_parts).to eq([])
    end
  end

  describe "#gem_name" do
    it "returns the last path part" do
      resolver = described_class.new(["org", "team", "my-gem"])
      expect(resolver.gem_name).to eq("my-gem")
    end

    it "returns nil for empty path" do
      resolver = described_class.new([])
      expect(resolver.gem_name).to be_nil
    end

    it "returns the only element for single-element path" do
      resolver = described_class.new(["my-gem"])
      expect(resolver.gem_name).to eq("my-gem")
    end
  end

  describe "#scope_path" do
    it "returns all parts except the last" do
      resolver = described_class.new(["org", "team", "my-gem"])
      expect(resolver.scope_path).to eq(["org", "team"])
    end

    it "returns empty array for single-element path" do
      resolver = described_class.new(["my-gem"])
      expect(resolver.scope_path).to eq([])
    end

    it "returns empty array for empty path" do
      resolver = described_class.new([])
      expect(resolver.scope_path).to eq([])
    end
  end

  describe "#scope" do
    it "returns nil for empty scope path" do
      resolver = described_class.new(["my-gem"])
      expect(resolver.scope).to be_nil
    end

    it "creates and returns a single-level scope" do
      resolver = described_class.new(["org", "my-gem"])
      scope = resolver.scope

      expect(scope).not_to be_nil
      expect(scope[:name]).to eq("org")
      expect(scope[:parent_id]).to be_nil
    end

    it "creates and returns nested scopes" do
      resolver = described_class.new(["org", "team", "my-gem"])
      scope = resolver.scope

      expect(scope).not_to be_nil
      expect(scope[:name]).to eq("team")

      parent = db[:scopes].where(id: scope[:parent_id]).first
      expect(parent[:name]).to eq("org")
      expect(parent[:parent_id]).to be_nil
    end

    it "reuses existing scopes" do
      # Create a scope first
      org_id = db[:scopes].insert(name: "org", parent_id: nil, created_at: Time.now, updated_at: Time.now)

      resolver = described_class.new(["org", "my-gem"])
      scope = resolver.scope

      expect(scope[:id]).to eq(org_id)
      expect(db[:scopes].count).to eq(1)
    end

    it "handles up to 3 levels of nesting" do
      resolver = described_class.new(["org", "team", "subteam", "my-gem"])
      scope = resolver.scope

      expect(scope[:name]).to eq("subteam")

      # Verify the hierarchy
      level2 = db[:scopes].where(id: scope[:parent_id]).first
      expect(level2[:name]).to eq("team")

      level1 = db[:scopes].where(id: level2[:parent_id]).first
      expect(level1[:name]).to eq("org")
      expect(level1[:parent_id]).to be_nil
    end
  end

  describe "#root_scope?" do
    it "returns true for empty scope path" do
      resolver = described_class.new(["my-gem"])
      expect(resolver.root_scope?).to be true
    end

    it "returns false for non-empty scope path" do
      resolver = described_class.new(["org", "my-gem"])
      expect(resolver.root_scope?).to be false
    end
  end
end
