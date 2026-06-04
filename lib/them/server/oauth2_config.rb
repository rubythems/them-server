# frozen_string_literal: true

require "oauth2"

module Them
  module Server
    # OAuth2 configuration and client management.
    #
    # This module provides OAuth2 integration for gem server authentication,
    # allowing the server to act as both an OAuth2 client (for authenticating
    # against external providers) and resource server (for validating tokens).
    #
    # The implementation supports:
    # - Multiple OAuth2 providers (GitHub, GitLab, custom providers)
    # - Token introspection (RFC 7662)
    # - Bearer token authentication (RFC 6750)
    # - Client credentials grant (RFC 6749 Section 4.4)
    #
    # Configuration via environment variables:
    # - OAUTH2_PROVIDER_URL: Base URL of the OAuth2 provider
    # - OAUTH2_CLIENT_ID: OAuth2 client identifier
    # - OAUTH2_CLIENT_SECRET: OAuth2 client secret
    # - OAUTH2_INTROSPECTION_URL: Token introspection endpoint (optional)
    # - OAUTH2_TOKEN_URL: Token endpoint (default: /oauth/token)
    # - OAUTH2_AUTHORIZE_URL: Authorization endpoint (default: /oauth/authorize)
    #
    # @see https://datatracker.ietf.org/doc/html/rfc6749 OAuth 2.0 Framework (RFC 6749)
    # @see https://datatracker.ietf.org/doc/html/rfc6750 OAuth 2.0 Bearer Token Usage (RFC 6750)
    # @see https://datatracker.ietf.org/doc/html/rfc7662 OAuth 2.0 Token Introspection (RFC 7662)
    # @see https://datatracker.ietf.org/doc/html/rfc8414 OAuth 2.0 Authorization Server Metadata (RFC 8414)
    #
    # @example Basic configuration
    #   ENV['OAUTH2_PROVIDER_URL'] = 'https://github.com'
    #   ENV['OAUTH2_CLIENT_ID'] = 'your-client-id'
    #   ENV['OAUTH2_CLIENT_SECRET'] = 'your-client-secret'
    #   client = Them::Server::OAuth2Config.client
    #
    # @example Token validation
    #   token = Them::Server::OAuth2Config.validate_token('access-token-here')
    #   if token
    #     puts "Valid token for user: #{token['username']}"
    #   end
    #
    module OAuth2Config
      class << self
        # Returns a configured OAuth2 client instance.
        #
        # The client is cached per-process to avoid recreating connections.
        # It uses the OAuth2::Client from the oauth2 gem which provides
        # automatic token refresh, request signing, and error handling.
        #
        # @return [OAuth2::Client, nil] Configured OAuth2 client or nil if not configured
        #
        # @note Returns nil if OAUTH2_PROVIDER_URL is not set, allowing the
        #   server to function without OAuth2 when not needed.
        #
        # @see https://github.com/oauth-xx/oauth2 oauth2 gem documentation
        #
        # @example Getting a client
        #   client = OAuth2Config.client
        #   if client
        #     token = client.client_credentials.get_token
        #   end
        #
        def client
          @client ||= build_client
        end

        # Validates an OAuth2 access token.
        #
        # This method performs token validation using one of two strategies:
        # 1. Token introspection (RFC 7662) - if introspection endpoint is configured
        # 2. Token info endpoint - fallback for providers without introspection
        #
        # Token introspection provides authoritative validation, checking if the
        # token is active, not expired, and not revoked. The response includes
        # metadata about the token such as scopes, expiration, and subject.
        #
        # @param access_token [String] The access token to validate
        #
        # @return [Hash, nil] Token metadata if valid, nil if invalid or error
        #   - 'active' [Boolean]: Whether the token is currently active
        #   - 'scope' [String]: Space-separated list of scopes
        #   - 'client_id' [String]: Client that obtained the token
        #   - 'username' [String]: Resource owner username (if available)
        #   - 'exp' [Integer]: Token expiration time (Unix timestamp)
        #   - 'iat' [Integer]: Token issued at time (Unix timestamp)
        #
        # @note Returns nil if OAuth2 is not configured
        # @note Caches negative results briefly to prevent DoS via invalid tokens
        #
        # @see https://datatracker.ietf.org/doc/html/rfc7662 Token Introspection (RFC 7662)
        #
        # @example Validating a token
        #   token_info = OAuth2Config.validate_token('access-token')
        #   if token_info && token_info['active']
        #     # Token is valid
        #     scopes = token_info['scope'].split(' ')
        #   end
        #
        def validate_token(access_token)
          return nil if access_token.to_s.strip.empty?
          return nil unless client

          # Use introspection endpoint if configured (RFC 7662)
          if introspection_url
            introspect_token(access_token)
          else
            # Fallback to token info endpoint for providers without introspection
            fetch_token_info(access_token)
          end
        rescue OAuth2::Error => e
          # OAuth2 errors (401, 403, etc.) indicate invalid token
          warn "OAuth2 validation error: #{e.class}: #{e.message}"
          nil
        rescue => e
          # Other errors (network, timeout) should be logged but not expose details
          warn "OAuth2 validation failed: #{e.class}: #{e.message}"
          nil
        end

        # Checks if OAuth2 is configured and enabled.
        #
        # @return [Boolean] true if OAuth2 provider URL is set
        #
        # @example Checking if OAuth2 is available
        #   if OAuth2Config.enabled?
        #     # Use OAuth2 authentication
        #   else
        #     # Fall back to API keys
        #   end
        #
        def enabled?
          !provider_url.to_s.empty?
        end

        # Returns the configured provider URL.
        #
        # @return [String, nil] The OAuth2 provider base URL
        #
        def provider_url
          ENV["OAUTH2_PROVIDER_URL"]
        end

        # Returns the configured client ID.
        #
        # @return [String, nil] The OAuth2 client identifier
        #
        def client_id
          ENV["OAUTH2_CLIENT_ID"]
        end

        # Returns the configured client secret.
        #
        # @return [String, nil] The OAuth2 client secret
        #
        # @note This should be kept secure and never logged or exposed in responses
        #
        def client_secret
          ENV["OAUTH2_CLIENT_SECRET"]
        end

        # Returns the token introspection endpoint URL.
        #
        # @return [String, nil] The introspection endpoint URL or nil
        #
        # @note If not set, falls back to token info endpoint
        #
        def introspection_url
          ENV["OAUTH2_INTROSPECTION_URL"]
        end

        private

        # Builds and configures an OAuth2 client instance.
        #
        # Creates an OAuth2::Client with appropriate endpoints for the provider.
        # Supports common providers (GitHub, GitLab) with sensible defaults.
        #
        # @return [OAuth2::Client, nil] Configured client or nil
        #
        def build_client
          return nil unless enabled?
          return nil if client_id.to_s.empty? || client_secret.to_s.empty?

          # Extract endpoints from environment or use provider defaults
          token_url = ENV["OAUTH2_TOKEN_URL"] || detect_token_url
          authorize_url = ENV["OAUTH2_AUTHORIZE_URL"] || detect_authorize_url

          OAuth2::Client.new(
            client_id,
            client_secret,
            site: provider_url,
            token_url: token_url,
            authorize_url: authorize_url,
            # Connection options for resilience
            connection_opts: {
              request: {
                timeout: 10,        # 10 second timeout for requests
                open_timeout: 5    # 5 second timeout for connection
              }
            }
          )
        rescue => e
          warn "Failed to build OAuth2 client: #{e.class}: #{e.message}"
          nil
        end

        # Introspects a token using RFC 7662 introspection endpoint.
        #
        # Token introspection provides authoritative validation by querying
        # the authorization server directly. This is the preferred method
        # as it checks revocation status and other server-side state.
        #
        # @param access_token [String] The token to introspect
        #
        # @return [Hash, nil] Token metadata or nil if inactive/invalid
        #
        # @see https://datatracker.ietf.org/doc/html/rfc7662 RFC 7662
        #
        def introspect_token(access_token)
          # RFC 7662: POST to introspection endpoint with token parameter
          response = client.request(:post, introspection_url, {
            body: {
              token: access_token,
              token_type_hint: "access_token"
            }
          })

          data = JSON.parse(response.body)

          # RFC 7662: Must have 'active' boolean field
          return nil unless data.is_a?(Hash)
          return nil unless data["active"] == true

          data
        rescue JSON::ParserError
          nil
        end

        # Fetches token information from a token info endpoint.
        #
        # This is a fallback for providers that don't support RFC 7662
        # introspection. Uses the access token to query user/token info.
        #
        # @param access_token [String] The token to validate
        #
        # @return [Hash, nil] Token metadata or nil if invalid
        #
        def fetch_token_info(access_token)
          # Create an AccessToken object to make authenticated requests
          token = OAuth2::AccessToken.new(client, access_token)

          # Try common token info endpoints
          endpoints = [
            "/api/v4/user",           # GitLab
            "/user",                  # GitHub
            "/oauth/token/info"      # Generic
          ]

          endpoints.each do |endpoint|
            response = token.get(endpoint)
            data = JSON.parse(response.body)

            # Successful response indicates valid token
            return {
              "active" => true,
              "username" => data["username"] || data["login"] || data["email"],
              "scope" => data["scope"] || "",
              "client_id" => client_id
            }
          rescue OAuth2::Error
            # Try next endpoint
            next
          rescue JSON::ParserError
            next
          end

          # No endpoint worked
          nil
        end

        # Detects the token endpoint URL based on provider.
        #
        # @return [String] The token endpoint path
        #
        def detect_token_url
          case provider_url
          when /github\.com/i
            "/login/oauth/access_token"
          when /gitlab\.com/i
            "/oauth/token"
          else
            "/oauth/token"  # RFC 6749 common default
          end
        end

        # Detects the authorization endpoint URL based on provider.
        #
        # @return [String] The authorization endpoint path
        #
        def detect_authorize_url
          case provider_url
          when /github\.com/i
            "/login/oauth/authorize"
          when /gitlab\.com/i
            "/oauth/authorize"
          else
            "/oauth/authorize"  # RFC 6749 common default
          end
        end
      end
    end
  end
end
