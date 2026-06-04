# frozen_string_literal: true

module Them
  module Server
    module Relations
      class ScopeOwners < Them::Server::DB::Relation
        schema(:scope_owners, infer: true)

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
