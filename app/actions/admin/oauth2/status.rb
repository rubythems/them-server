# frozen_string_literal: true

require "json"
require_relative "../../../../config/database"
require "gem/server/oauth2_config"

module Gem
  module Server
    module Actions
      module Admin
        module OAuth2
          # Displays OAuth2 configuration and status.
          #
          # This action provides visibility into the OAuth2 integration status,
          # showing whether OAuth2 is enabled, which provider is configured,
          # and basic connectivity tests.
          #
          # @see Gem::Server::OAuth2Config
          #
          class Status < Gem::Server::Action
            def handle(request, response)
              status = {
                enabled: Gem::Server::OAuth2Config.enabled?,
                provider_url: Gem::Server::OAuth2Config.provider_url,
                client_id: Gem::Server::OAuth2Config.client_id,
                has_client_secret: !Gem::Server::OAuth2Config.client_secret.to_s.empty?,
                introspection_enabled: !Gem::Server::OAuth2Config.introspection_url.to_s.empty?,
                introspection_url: Gem::Server::OAuth2Config.introspection_url,
              }

              # Test connectivity if enabled
              if status[:enabled]
                begin
                  client = Gem::Server::OAuth2Config.client
                  status[:client_configured] = !client.nil?
                rescue StandardError => e
                  status[:client_configured] = false
                  status[:error] = "#{e.class}: #{e.message}"
                end
              end

              response.format = :json
              response.status = 200
              response.body = JSON.generate(status)
            end
          end
        end
      end
    end
  end
end

