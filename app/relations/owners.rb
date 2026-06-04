# frozen_string_literal: true

module Gem
  module Server
    module Relations
      class Owners < Gem::Server::DB::Relation
        schema(:owners, infer: true)

        def by_name(name)
          where(name: name)
        end

        def by_api_key(api_key)
          where(api_key: api_key)
        end

        def by_email(email)
          where(email: email)
        end
      end
    end
  end
end
