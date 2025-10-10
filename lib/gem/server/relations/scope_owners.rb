# frozen_string_literal: true

module Gem
  module Server
    module Relations
      class ScopeOwners < ROM::Relation[:sql]
        schema(:scope_owners, infer: true) do
          associations do
            belongs_to :scope
            belongs_to :owner
          end
        end

        def by_scope(scope_id)
          where(scope_id: scope_id)
        end

        def by_owner(owner_id)
          where(owner_id: owner_id)
        end
      end
    end
  end
end
