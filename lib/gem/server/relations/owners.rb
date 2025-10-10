# frozen_string_literal: true

module Gem
  module Server
    module Relations
      class Owners < ROM::Relation[:sql]
        schema(:owners, infer: true) do
          associations do
            has_many :gem_owners
            has_many :gems, through: :gem_owners
            has_many :scope_owners
            has_many :scopes, through: :scope_owners
          end
        end

        def by_name(name)
          where(name: name)
        end

        def by_api_key(api_key)
          where(api_key: api_key)
        end
      end
    end
  end
end
