# frozen_string_literal: true

module Gem
  module Server
    module Actions
      module Auth
        class Register < Gem::Server::Action
          def handle(request, response)
            # Check if already logged in
            if request.session[:user_id]
              response.status = 302
              response.headers["Location"] = "/auth/dashboard"
              return
            end

            error = request.params[:error]
            response.render view, error: error
          end
        end
      end
    end
  end
end
