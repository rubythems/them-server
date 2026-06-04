# frozen_string_literal: true

Sequel.migration do
  change do
    alter_table(:owners) do
      add_column :account_id, Integer, null: true
      add_index :account_id, unique: true
    end
  end
end
