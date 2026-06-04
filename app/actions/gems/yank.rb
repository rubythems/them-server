# frozen_string_literal: true

require_relative "../../../config/database"
require "them/server/authenticator"

module Them
  module Server
    module Actions
      module Gems
        class Yank < Them::Server::Action
          def handle(request, response)
            path_param = request.params[:path] || ""
            path_parts = path_param.split("/").reject(&:empty?)
            version = request.params[:version]

            # Parse path: /{scope-path}/{gem}/versions/{version}
            # Remove 'versions' from the path
            if path_parts.last == "versions"
              path_parts.pop
            end

            gem_name = path_parts.last
            scope_path = path_parts[0..-2]

            resolver = ScopeResolver.new(scope_path, include_gem_name: false)
            scope = resolver.scope(create: false)
            db = Database.db

            # Authentication: Use unified OAuth2-enabled authenticator
            auth_result = Them::Server::Authenticator.authenticate(request.env)

            unless auth_result[:authenticated]
              response.headers["content-type"] = "text/plain; charset=utf-8"
              response.headers["WWW-Authenticate"] = 'Bearer realm="them-server"' if Them::Server::OAuth2Config.enabled?
              response.body = Them::Server::OAuth2Config.enabled? ? "API key or OAuth2 token required" : "API key required"
              response.status = 401
              return
            end

            # Look up owner by API key/token
            api_key = auth_result[:token]
            owner = db[:owners].where(api_key: api_key).first
            unless owner
              response.headers["content-type"] = "text/plain; charset=utf-8"
              response.body = "Invalid API key"
              response.status = 401
              return
            end

            # Find gem
            gem_record = db[:gems].where(
              name: gem_name,
              scope_id: scope&.fetch(:id, nil),
              version: version
            ).first

            unless gem_record
              response.headers["Content-Type"] = "text/plain; charset=utf-8"
              response.body = "Gem not found"
              response.status = 404
              return
            end

            # Check permission: owner must be gem owner
            is_gem_owner = db[:gem_owners].where(
              gem_id: gem_record[:id],
              owner_id: owner[:id]
            ).first

            unless is_gem_owner
              response.headers["Content-Type"] = "text/plain; charset=utf-8"
              response.body = "Not authorized to yank this gem"
              response.status = 403
              return
            end

            # Yank
            db[:gems].where(id: gem_record[:id]).update(
              yanked: true,
              updated_at: Time.now
            )

            response.headers["Content-Type"] = "text/plain; charset=utf-8"
            response.body = "Gem yanked"
            response.status = 200
          end
        end
      end
    end
  end
end
