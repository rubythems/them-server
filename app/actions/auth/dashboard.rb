# frozen_string_literal: true

module Gem
  module Server
    module Actions
      module Auth
        class Dashboard < Gem::Server::Action
          def handle(request, response)
            # Check if logged in
            unless request.session[:user_id]
              response.status = 302
              response.headers["Location"] = "/auth/login?error=login_required"
              return
            end

            user_id = request.session[:user_id]
            db = Gem::Server::Database.db

            # Get user info
            owner = db[:owners].where(id: user_id).first
            unless owner
              request.session.clear
              response.status = 302
              response.headers["Location"] = "/auth/login?error=session_invalid"
              return
            end

            # Get owned gems with scope information
            owned_gems = db[:gem_owners]
              .join(:gems, id: :gem_id)
              .left_join(:scopes, id: Sequel[:gems][:scope_id])
              .where(Sequel[:gem_owners][:owner_id] => user_id)
              .select(
                Sequel[:gems][:id],
                Sequel[:gems][:name],
                Sequel[:gems][:version],
                Sequel[:gems][:yanked],
                Sequel[:gems][:created_at],
                Sequel[:scopes][:path].as(:scope_path)
              )
              .order(Sequel.desc(Sequel[:gems][:created_at]))
              .all

            response.render view,
                           owner: owner,
                           gems: owned_gems,
                           user_name: owner[:name],
                           user_email: owner[:email]
          end
        end
      end
    end
  end
end
