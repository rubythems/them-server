# frozen_string_literal: true

module Gem
  module Server
    module Actions
      module Auth
        class Logout < Gem::Server::Action
          def handle(request, response)
            request.session.clear

            response.status = 302
            response.headers["Location"] = "/auth/login?logged_out=true"
          end
        end
      end
    end
  end
end
