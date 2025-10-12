# frozen_string_literal: true

require "hanami"
require "rack/session/cookie"
require "omniauth"
require "omniauth-identity"

module Gem
  module Server
    # Middleware to handle binary gem uploads without going through Hanami router
    class DirectGemUploadHandler
      def initialize(app)
        @app = app
      end

      def call(env)
        # For gem uploads, handle them directly without going through Hanami's router
        # This prevents the router from trying to parse the binary data as parameters
        if env["REQUEST_METHOD"] == "POST" && gem_upload_path?(env["PATH_INFO"])
          # Load the action directly and call it
          require_relative "../app/actions/gems/create"
          action = Gem::Server::Actions::Gems::Create.new

          # Call the action directly with a Rack request/response
          status, headers, body = action.call(env)
          [status, headers, body]
        else
          @app.call(env)
        end
      end

      private

      def gem_upload_path?(path)
        return false unless path

        # Match /api/v1/gems and scoped gem uploads like /api/v1/gems/scope/path
        # Also match root-level gem pushes like /my-scope/my-gem
        path.start_with?("/api/v1/gems") ||
          (path.start_with?("/") && !path.start_with?("/federation") &&
           !path.start_with?("/admin") && path != "/" &&
           !path.include?(".") && !path.include?("/versions/"))
      end
    end

    class Application < Hanami::App
      config.logger.level = :info
      config.logger.stream = $stdout

      # Add session middleware for authentication
      config.middleware.use Rack::Session::Cookie,
                            secret: ENV.fetch("SESSION_SECRET", SecureRandom.hex(64)),
                            key: "gem_server.session",
                            same_site: :lax,
                            max_age: 86400 * 30 # 30 days

      # Add OmniAuth middleware for authentication
      config.middleware.use OmniAuth::Builder do
        provider :identity,
                 fields: [:email, :name],
                 model: Gem::Server::Models::Identity,
                 on_failed_registration: lambda { |env|
                   [302, {"Location" => "/auth/register?error=registration_failed"}, []]
                 }
      end

      # Add middleware to handle gem uploads directly, bypassing Hanami router
      # This must be early in the middleware stack, before the router
      config.middleware.use DirectGemUploadHandler

      # Configure inflections for OAuth2 naming conventions
      # This allows oauth2_config.rb to define OAuth2Config instead of Oauth2Config
      config.inflections do |inflections|
        inflections.acronym "OAuth2"
      end
    end
  end
end
