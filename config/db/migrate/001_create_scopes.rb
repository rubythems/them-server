# frozen_string_literal: true

Sequel.migration do
  change do
    create_table :scopes do
      primary_key :id
      String :name, null: false
      foreign_key :parent_id, :scopes, null: true
      DateTime :created_at, null: false
      DateTime :updated_at, null: false

      index :name
      index :parent_id
    end
  end
end
