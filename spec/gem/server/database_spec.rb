# frozen_string_literal: true

require "spec_helper"

RSpec.describe Gem::Server::Database do
  describe ".db" do
    it "returns a Sequel database connection" do
      expect(described_class.db).to be_a(Sequel::Database)
    end

    it "uses SQLite adapter" do
      expect(described_class.db.database_type).to eq(:sqlite)
    end
  end

  describe ".migrate" do
    it "runs migrations successfully" do
      expect { described_class.migrate }.not_to raise_error
    end

    it "creates all required tables" do
      db = described_class.db
      expect(db.tables).to include(:scopes, :owners, :gems, :gem_owners, :scope_owners)
    end
  end

  describe "schema" do
    let(:db) { described_class.db }

    it "creates scopes table with correct columns" do
      expect(db.schema(:scopes).map(&:first)).to include(:id, :name, :parent_id, :created_at, :updated_at)
    end

    it "creates owners table with correct columns" do
      expect(db.schema(:owners).map(&:first)).to include(:id, :name, :public_key, :api_key, :created_at, :updated_at)
    end

    it "creates gems table with correct columns" do
      expect(db.schema(:gems).map(&:first)).to include(:id, :name, :version, :scope_id, :file_path, :yanked, :created_at, :updated_at)
    end

    it "creates gem_owners join table" do
      expect(db.schema(:gem_owners).map(&:first)).to include(:id, :gem_id, :owner_id, :created_at)
    end

    it "creates scope_owners join table" do
      expect(db.schema(:scope_owners).map(&:first)).to include(:id, :scope_id, :owner_id, :created_at)
    end
  end
end
