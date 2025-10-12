# frozen_string_literal: true

Sequel.migration do
  change do
    alter_table :owners do
      add_column :email, String
      add_column :password_digest, String

      add_index :email, unique: true
    end
  end
end

