# frozen_string_literal: true

require "rubygems/package"
require "tempfile"
require "them/server/scope_resolver"
require_relative "../../../config/database"
require "them/server/federation_broadcaster"
require "them/server/authenticator"

module Them
  module Server
    module Actions
      module Gems
        class Create < Them::Server::Action
          # Skip automatic parameter parsing to handle binary gem data
          # In Hanami 2.2, we handle the raw request body manually

          def handle(request, response)
            # Log request details for debugging
            if ENV["HANAMI_ENV"] == "test"
              File.open("tmp/hanami_action_debug.log", "a") do |f|
                f.puts "\n=== [#{Time.now}] Hanami Action Called ==="
                f.puts "Content-Type: #{request.env['CONTENT_TYPE']}"
                f.puts "Original Content-Type: #{request.env['HTTP_X_ORIGINAL_CONTENT_TYPE']}"
                f.puts "Content-Length: #{request.env['CONTENT_LENGTH']}"
                f.puts "PATH_INFO: #{request.env['PATH_INFO']}"
              end
            end

            # IMPORTANT: Do not call request.params here; it can force Rack to parse the request body
            # as URL-encoded data, which breaks when the body contains raw gem bytes.

            # Derive scope path parts from PATH_INFO without touching params
            path_info = request.env["PATH_INFO"].to_s
            # Normalize and drop the API prefix if present (e.g., /api/v1/gems)
            segments = path_info.split("/").reject(&:empty?)
            path_parts = if segments[0] == "api" && segments[1] == "v1" && segments[2] == "gems"
                           segments[3..] || []
                         else
                           segments
                         end

            # Determine upload mode: multipart form vs. raw body
            # Use original content type if it was saved by middleware
            content_type = request.env["HTTP_X_ORIGINAL_CONTENT_TYPE"] || request.env["CONTENT_TYPE"].to_s
            file = nil
            content_length = request.env["CONTENT_LENGTH"].to_i

            multipart_params = nil
            if content_type.start_with?("multipart/form-data")
              # Safe to parse multipart only (Rack won't attempt URL-decode raw octet-stream)
              rack_req = ::Rack::Request.new(request.env)
              multipart_params = rack_req.params
              file_param = multipart_params["gem"] || multipart_params["file"]
              # Rack can wrap uploads in a hash with :tempfile
              if file_param.respond_to?(:read)
                file = file_param
              elsif file_param.respond_to?(:[]) && file_param[:tempfile]
                file = file_param[:tempfile]
              end
            elsif content_type.start_with?("application/octet-stream")
              # Treat as raw body stream only if there's a non-zero Content-Length
              file = request.body if content_length.positive?
            else
              # Other content types (e.g., application/x-www-form-urlencoded) are not valid for gem upload
              file = nil
            end

            # Reject if no file or file is empty
            if !(file && file.respond_to?(:read)) || io_empty?(file, content_length)
              response.headers["content-type"] = "text/plain; charset=utf-8"
              response.body = "No gem file provided"
              response.status = 400
              return
            end

            resolver = ScopeResolver.new(path_parts, include_gem_name: false)
            scope = resolver.scope(create: true)  # Create scopes during push
            db = Database.db

            # Authentication: Use unified OAuth2-enabled authenticator
            auth_result = Them::Server::Authenticator.authenticate(request.env)

            # Allow multipart form fallback for backwards compatibility
            if !auth_result[:authenticated] && multipart_params
              api_key = (multipart_params["rubygems_api_key"] || multipart_params["api_key"]).to_s.strip
              unless api_key.empty?
                auth_result = {
                  authenticated: true,
                  scheme: :form_param,
                  user: api_key,
                  token: api_key,
                  scopes: [],
                  token_info: nil,
                }
              end
            end

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

            # Check permission: owner must be scope owner
            if scope
              is_scope_owner = db[:scope_owners].where(scope_id: scope[:id], owner_id: owner[:id]).first
              unless is_scope_owner
                response.headers["content-type"] = "text/plain; charset=utf-8"
                response.body = "Not authorized to push to this scope"
                response.status = 403
                return
              end
            end

            temp_file = nil
            begin
              # Parse gem file for metadata
              temp_file = Tempfile.new(["gem", ".gem"])
              temp_file.binmode
              # Ensure we read from the start
              begin
                file.rewind if file.respond_to?(:rewind)
              rescue StandardError
                # Ignore if cannot rewind (e.g., non-rewindable IO). We'll read as-is.
              end
              temp_file.write(file.read)
              temp_file.rewind

              spec = ::Gem::Package.new(temp_file.path).spec
              name = spec.name
              version = spec.version.to_s

              # Store the gem file
              Dir.mkdir("gems") unless Dir.exist?("gems")
              file_path = "gems/#{name}-#{version}.gem"

              temp_file.rewind
              File.binwrite(file_path, temp_file.read)

              # Insert into database
              gem_id = db[:gems].insert(
                name: name,
                version: version,
                scope_id: scope&.fetch(:id),
                file_path: file_path,
                yanked: false,
                created_at: Time.now,
                updated_at: Time.now,
                )

              # Add owner as gem owner
              db[:gem_owners].insert(
                gem_id: gem_id,
                owner_id: owner[:id],
                created_at: Time.now,
                )

              # Optional federation broadcast
              Them::Server::FederationBroadcaster.broadcast_gem(
                name: name,
                version: version,
                scope_path: path_parts,
                file_path: file_path,
                )

              response.headers["content-type"] = "text/plain; charset=utf-8"
              response.body = (path_parts.empty? ? "Successfully registered gem: #{name} (#{version})" : "Gem #{name} #{version} pushed successfully")
              response.status = 201
            rescue => e
              response.headers["content-type"] = "text/plain; charset=utf-8"
              response.body = "Error pushing gem: #{sanitize_text(e.message)}"
              response.status = 500
            ensure
              if temp_file
                temp_file.close
                temp_file.unlink
              end
            end
          end

          private


          def io_empty?(io, content_length)
            # If this is the rack input stream, rely on Content-Length
            return true if (io.respond_to?(:path) ? false : true) && content_length.to_i <= 0

            # For UploadedFile/Tempfile
            if io.respond_to?(:size)
              return io.size.to_i <= 0
            end

            # Fallback: try to peek 1 byte without consuming
            begin
              original_pos = io.pos
            rescue StandardError
              original_pos = nil
            end
            begin
              byte = io.read(1)
              return true if byte.nil? || byte.bytesize <= 0
            ensure
              begin
                if original_pos
                  io.seek(original_pos, IO::SEEK_SET)
                elsif io.respond_to?(:rewind)
                  io.rewind
                end
              rescue StandardError
                # ignore
              end
            end
            false
          end

          def sanitize_text(str)
            s = str.to_s
            # Ensure UTF-8-safe output by encoding from binary with replacement
            begin
              return s.encode("UTF-8", invalid: :replace, undef: :replace, replace: "?") if s.encoding == Encoding::UTF_8 && s.valid_encoding?
              s.encode("UTF-8", "binary", invalid: :replace, undef: :replace, replace: "?")
            rescue StandardError
              # Fallback: use scrub if available
              s.force_encoding("UTF-8").scrub("?")
            end
          end
        end
      end
    end
  end
end
