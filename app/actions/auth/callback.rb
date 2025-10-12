# frozen_string_literal: true

module Gem
  module Server
    module Actions
      module Auth
        class Callback < Gem::Server::Action
          def handle(request, response)
            auth = request.env["omniauth.auth"]

            if auth
              # Find or create owner from identity
              owner_id = auth["uid"]
              db = Gem::Server::Database.db
              owner = db[:owners].where(id: owner_id).first

              if owner
                # Store user session
                request.session[:user_id] = owner[:id]
                request.session[:user_name] = owner[:name]
                request.session[:user_email] = owner[:email]

                response.status = 302
                response.headers["Location"] = "/auth/dashboard"
              else
                response.status = 302
                response.headers["Location"] = "/auth/login?error=user_not_found"
              end
            else
              response.status = 302
              response.headers["Location"] = "/auth/login?error=auth_failed"
            end
          end
        end
      end
    end
  end
end
