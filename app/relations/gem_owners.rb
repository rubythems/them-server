# frozen_string_literal: true

module Gem
  module Server
    module Relations
      class GemOwners < ROM::Relation[:sql]
        schema(:gem_owners, infer: true)

        def by_gem(gem_id)
          where(gem_id: gem_id)
        end

        def by_owner(owner_id)
          where(owner_id: owner_id)
        end
      end
    end
  end
end
