# frozen_string_literal: true

require "json"
require "gem/server/scope_resolver"
require_relative "../../../config/database"

module Gem
  module Server
    module Actions
      module Gems
        class Show < Gem::Server::Action
          def handle(request, response)
            path_param = request.params[:path] || ""
            path_parts = path_param.split("/").reject(&:empty?)

            resolver = ScopeResolver.new(path_parts)
            db = Database.db

            # Try to interpret last part as gem name first
            if resolver.gem_name
              scope = resolver.scope(create: false)

              gem_record = db[:gems]
                .where(name: resolver.gem_name, scope_id: scope&.fetch(:id, nil), yanked: false)
                .order(:version)
                .last

              if gem_record
                # Found a gem - serve it
                response.body = File.read(gem_record[:file_path])
                response.headers["content-type"] = "application/octet-stream"
                response.headers["content-disposition"] = "attachment; filename=\"#{resolver.gem_name}-#{gem_record[:version]}.gem\""
                response.status = 200
                return
              end
            end

            # No gem found, or no gem name - list gems in scope
            # Treat entire path as scope path for listing
            scope_resolver = ScopeResolver.new(path_parts, include_gem_name: false)
            scope = scope_resolver.scope(create: false)

            if scope.nil? && !path_parts.empty?
              response.status = 404
              response.body = "Gem not found"
              return
            end

            gems = if scope
              db[:gems].where(scope_id: scope[:id], yanked: false).all
            elsif path_parts.empty?
              # Root scope - list all gems with no scope_id
              db[:gems].where(scope_id: nil, yanked: false).all
            else
              # Scope doesn't exist - return empty list
              []
            end

            response.format = :json
            response.body = JSON.generate(gems.map { |g| {name: g[:name], version: g[:version]} })
            response.status = 200
          end
        end
      end
    end
  end
end
