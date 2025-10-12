# frozen_string_literal: true

module Gem
  module Server
    module Relations
      class Scopes < ROM::Relation[:sql]
        schema(:scopes, infer: true)

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
