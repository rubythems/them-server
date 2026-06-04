# frozen_string_literal: true

Sequel.migration do
  change do
    create_table :gem_owners do
      primary_key :id
      foreign_key :gem_id, :gems, null: false
      foreign_key :owner_id, :owners, null: false
      DateTime :created_at, null: false

      index [:gem_id, :owner_id], unique: true
    end

    create_table :scope_owners do
      primary_key :id
      foreign_key :scope_id, :scopes, null: false
      foreign_key :owner_id, :owners, null: false
      DateTime :created_at, null: false

      index [:scope_id, :owner_id], unique: true
    end
  end
end
