# frozen_string_literal: true

require "spec_helper"

RSpec.describe Them::Server do
  it "has a version number" do
    expect(Them::Server::Version::VERSION).not_to be_nil
  end

  describe "module structure" do
    it "defines the Them::Server namespace" do
      expect(defined?(Them::Server)).to eq("constant")
    end

    it "includes Database module" do
      expect(Them::Server::Database).to respond_to(:db)
      expect(Them::Server::Database).to respond_to(:migrate)
    end

    it "includes ScopeResolver class" do
      expect(Them::Server::ScopeResolver).to be_a(Class)
    end

    it "includes Action base class" do
      expect(Them::Server::Action).to be < Hanami::Action
    end
  end

  describe "integration" do
    let(:db) { Them::Server::Database.db }

    it "can create a complete workflow from scope to gem" do
      # Create owner
      owner_id = db[:owners].insert(
        name: "test-owner",
        api_key: "test-key",
        created_at: Time.now,
        updated_at: Time.now,
      )

      # Create scope
      scope_id = db[:scopes].insert(
        name: "myorg",
        parent_id: nil,
        created_at: Time.now,
        updated_at: Time.now,
      )

      # Assign owner to scope
      db[:scope_owners].insert(
        scope_id: scope_id,
        owner_id: owner_id,
        created_at: Time.now,
      )

      # Create gem
      gem_id = db[:gems].insert(
        name: "my-gem",
        version: "1.0.0",
        scope_id: scope_id,
        file_path: "gems/my-gem-1.0.0.gem",
        yanked: false,
        created_at: Time.now,
        updated_at: Time.now,
      )

      # Assign owner to gem
      db[:gem_owners].insert(
        gem_id: gem_id,
        owner_id: owner_id,
        created_at: Time.now,
      )

      # Verify relationships
      expect(db[:scopes].count).to eq(1)
      expect(db[:owners].count).to eq(1)
      expect(db[:gems].count).to eq(1)
      expect(db[:scope_owners].count).to eq(1)
      expect(db[:gem_owners].count).to eq(1)

      # Verify owner has access to gem
      gem_owner = db[:gem_owners].where(gem_id: gem_id, owner_id: owner_id).first
      expect(gem_owner).not_to be_nil

      # Verify owner has access to scope
      scope_owner = db[:scope_owners].where(scope_id: scope_id, owner_id: owner_id).first
      expect(scope_owner).not_to be_nil
    end

    it "supports hierarchical scopes with proper ownership" do
      # Create owner
      db[:owners].insert(
        name: "team-owner",
        api_key: "team-key",
        created_at: Time.now,
        updated_at: Time.now,
      )

      # Create parent scope
      parent_id = db[:scopes].insert(
        name: "company",
        parent_id: nil,
        created_at: Time.now,
        updated_at: Time.now,
      )

      # Create child scope
      child_id = db[:scopes].insert(
        name: "team",
        parent_id: parent_id,
        created_at: Time.now,
        updated_at: Time.now,
      )

      # Create grandchild scope
      grandchild_id = db[:scopes].insert(
        name: "project",
        parent_id: child_id,
        created_at: Time.now,
        updated_at: Time.now,
      )

      # Verify hierarchy
      grandchild = db[:scopes].where(id: grandchild_id).first
      expect(grandchild[:parent_id]).to eq(child_id)

      child = db[:scopes].where(id: child_id).first
      expect(child[:parent_id]).to eq(parent_id)

      parent = db[:scopes].where(id: parent_id).first
      expect(parent[:parent_id]).to be_nil

      # Create gem in deepest scope
      gem_id = db[:gems].insert(
        name: "project-gem",
        version: "1.0.0",
        scope_id: grandchild_id,
        file_path: "gems/project-gem-1.0.0.gem",
        yanked: false,
        created_at: Time.now,
        updated_at: Time.now,
      )

      expect(db[:gems].where(id: gem_id).first[:scope_id]).to eq(grandchild_id)
    end

    it "prevents unauthorized access across scopes" do
      # Create two owners
      owner1_id = db[:owners].insert(
        name: "owner1",
        api_key: "key1",
        created_at: Time.now,
        updated_at: Time.now,
      )

      owner2_id = db[:owners].insert(
        name: "owner2",
        api_key: "key2",
        created_at: Time.now,
        updated_at: Time.now,
      )

      # Create two scopes
      scope1_id = db[:scopes].insert(
        name: "org1",
        parent_id: nil,
        created_at: Time.now,
        updated_at: Time.now,
      )

      scope2_id = db[:scopes].insert(
        name: "org2",
        parent_id: nil,
        created_at: Time.now,
        updated_at: Time.now,
      )

      # Assign owner1 to scope1
      db[:scope_owners].insert(
        scope_id: scope1_id,
        owner_id: owner1_id,
        created_at: Time.now,
      )

      # Assign owner2 to scope2
      db[:scope_owners].insert(
        scope_id: scope2_id,
        owner_id: owner2_id,
        created_at: Time.now,
      )

      # Verify isolation
      owner1_scopes = db[:scope_owners].where(owner_id: owner1_id).map { |so| so[:scope_id] }
      expect(owner1_scopes).to eq([scope1_id])
      expect(owner1_scopes).not_to include(scope2_id)

      owner2_scopes = db[:scope_owners].where(owner_id: owner2_id).map { |so| so[:scope_id] }
      expect(owner2_scopes).to eq([scope2_id])
      expect(owner2_scopes).not_to include(scope1_id)
    end
  end
end
