# frozen_string_literal: true

Sequel.migration do
  change do
    create_table :known_servers do
      primary_key :id
      String :base_url, null: false
      String :public_key_b64, null: false
      TrueClass :subscribed, default: false
      DateTime :last_announced_at, null: true
      DateTime :last_seen_at, null: true
      DateTime :created_at, null: false
      DateTime :updated_at, null: false

      index :base_url, unique: true
      index :public_key_b64
      index :subscribed
    end

    create_table :federated_gems do
      primary_key :id
      String :name, null: false
      String :version, null: false
      foreign_key :scope_id, :scopes, null: true
      foreign_key :origin_server_id, :known_servers, null: false
      String :digest_sha256, null: false
      String :signature_b64, null: false
      DateTime :created_at, null: false

      index [:name, :version, :scope_id, :origin_server_id], unique: true, name: :idx_fed_gems_uniqueness
    end
  end
end

