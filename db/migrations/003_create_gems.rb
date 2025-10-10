# frozen_string_literal: true

Sequel.migration do
  change do
    create_table :gems do
      primary_key :id
      String :name, null: false
      String :version, null: false
      foreign_key :scope_id, :scopes, null: true
      String :file_path, null: false
      TrueClass :yanked, default: false
      DateTime :created_at, null: false
      DateTime :updated_at, null: false

      index [:name, :scope_id]
      index :version
      index :yanked
    end
  end
end
