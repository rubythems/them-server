# frozen_string_literal: true

module Gem
  module Server
    module Relations
      class Scopes < ROM::Relation[:sql]
        schema(:scopes, infer: true) do
          associations do
            belongs_to :parent, as: :parent_scope, foreign_key: :parent_id
            has_many :children, as: :child_scopes, foreign_key: :parent_id
            has_many :gems
            has_many :scope_owners
            has_many :owners, through: :scope_owners
          end
        end

        def by_name(name)
          where(name: name)
        end

        def root
          where(parent_id: nil)
        end
      end
    end
  end
end
