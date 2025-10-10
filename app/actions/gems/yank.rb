# frozen_string_literal: true

require "json"
require "gem/server/scope_resolver"
require_relative "../../../config/database"

module Gem
  module Server
    module Actions
      module Gems
        class Yank < Gem::Server::Action
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

            # Auth via headers
            api_key = extract_api_key_from_headers(request.env)
            unless api_key
              response.headers["Content-Type"] = "text/plain; charset=utf-8"
              response.body = "API key required"
              response.status = 401
              return
            end

            owner = db[:owners].where(api_key: api_key).first
            unless owner
              response.headers["Content-Type"] = "text/plain; charset=utf-8"
              response.body = "Invalid API key"
              response.status = 401
              return
            end

            # Find gem
            gem_record = db[:gems].where(
              name: gem_name,
              scope_id: scope&.fetch(:id, nil),
              version: version,
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
              owner_id: owner[:id],
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
              updated_at: Time.now,
            )

            response.headers["Content-Type"] = "text/plain; charset=utf-8"
            response.body = "Gem yanked"
            response.status = 200
          end

          private

          def extract_api_key_from_headers(env)
            auth = env["HTTP_AUTHORIZATION"]
            x_key = env["HTTP_X_API_KEY"].to_s.strip
            return x_key unless x_key.empty?

            return if auth.to_s.strip.empty?

            if (m = auth.match(/^Basic\s+(.+)$/i))
              require "base64"
              begin
                decoded = Base64.decode64(m[1])
                return decoded.split(":").first
              rescue StandardError
                return
              end
            elsif (m = auth.match(/^RubyGems\s+(.+)$/i))
              return m[1].to_s.strip
            elsif (m = auth.match(/^Bearer\s+(.+)$/i))
              return m[1].to_s.strip
            else
              return auth.strip unless auth.strip.include?(" ")
            end

            nil
          end
        end
      end
    end
  end
end
