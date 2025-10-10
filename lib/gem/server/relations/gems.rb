# frozen_string_literal: true

module Gem
  module Server
    module Relations
      class Gems < ROM::Relation[:sql]
        schema(:gems, infer: true) do
          associations do
            belongs_to :scope
            has_many :gem_owners
            has_many :owners, through: :gem_owners
          end
        end

        def by_name(name)
          where(name: name)
        end

        def by_scope(scope_id)
          where(scope_id: scope_id)
        end

        def not_yanked
          where(yanked: false)
        end

        def latest_version(name, scope_id = nil)
          by_name(name).by_scope(scope_id).order(:version).last
        end
      end
    end
  end
end
