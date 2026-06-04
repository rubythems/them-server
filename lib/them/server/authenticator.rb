# frozen_string_literal: true

require "base64"
require_relative "oauth2_config"

module Them
  module Server
    # Unified authentication handler supporting multiple authentication schemes.
    #
    # This module provides a comprehensive authentication system that supports:
    # - OAuth2 Bearer tokens (RFC 6750)
    # - RubyGems API keys
    # - HTTP Basic authentication (RFC 7617)
    # - Custom API key headers
    #
    # Authentication schemes are tried in order of security/preference:
    # 1. OAuth2 Bearer tokens (validated against provider)
    # 2. RubyGems API keys (X-Rubygems-Api-Key header)
    # 3. Custom API keys (X-Api-Key header)
    # 4. HTTP Basic authentication (username as key)
    # 5. Raw Authorization header (for backwards compatibility)
    #
    # @see https://datatracker.ietf.org/doc/html/rfc6750 OAuth 2.0 Bearer Token (RFC 6750)
    # @see https://datatracker.ietf.org/doc/html/rfc7617 HTTP Basic Authentication (RFC 7617)
    # @see https://guides.rubygems.org/rubygems-org-api/ RubyGems API Documentation
    #
    # @example Authenticating a request
    #   result = Them::Server::Authenticator.authenticate(request.env)
    #   if result[:authenticated]
    #     user = result[:user]
    #     scopes = result[:scopes]
    #   else
    #     # Authentication failed
    #   end
    #
    module Authenticator
      class << self
        # Authenticates a request using multiple authentication schemes.
        #
        # This method attempts authentication using various schemes in order of
        # preference. OAuth2 Bearer tokens are preferred as they provide the most
        # secure and feature-rich authentication (scopes, expiration, revocation).
        #
        # @param env [Hash] Rack environment hash containing HTTP headers
        #
        # @return [Hash] Authentication result with the following keys:
        #   - :authenticated [Boolean] Whether authentication succeeded
        #   - :scheme [Symbol] The authentication scheme used (:oauth2, :rubygems, :basic, :api_key, :raw)
        #   - :user [String, nil] The authenticated user identifier
        #   - :token [String, nil] The authentication token/key used
        #   - :scopes [Array<String>] List of authorized scopes (OAuth2 only)
        #   - :token_info [Hash, nil] Full token metadata (OAuth2 only)
        #
        # @example Successful OAuth2 authentication
        #   result = Authenticator.authenticate(env)
        #   # => {
        #   #   authenticated: true,
        #   #   scheme: :oauth2,
        #   #   user: "octocat",
        #   #   token: "gho_...",
        #   #   scopes: ["read", "write"],
        #   #   token_info: {...}
        #   # }
        #
        # @example Failed authentication
        #   result = Authenticator.authenticate(env)
        #   # => {
        #   #   authenticated: false,
        #   #   scheme: nil,
        #   #   user: nil,
        #   #   token: nil,
        #   #   scopes: [],
        #   #   token_info: nil
        #   # }
        #
        def authenticate(env)
          # Try OAuth2 Bearer token first (most secure)
          if (result = try_oauth2_bearer(env))
            return result
          end

          # Fall back to API key authentication
          if (result = try_api_key_auth(env))
            return result
          end

          # No authentication succeeded
          {
            authenticated: false,
            scheme: nil,
            user: nil,
            token: nil,
            scopes: [],
            token_info: nil,
          }
        end

        # Extracts an API key from request headers using legacy methods.
        #
        # This method maintains backwards compatibility with existing gem push
        # clients that use various header formats. It tries headers in order:
        # 1. X-Api-Key (custom header)
        # 2. X-Rubygems-Api-Key (RubyGems client)
        # 3. Authorization header with various schemes
        #
        # @param env [Hash] Rack environment hash
        #
        # @return [String, nil] Extracted API key or nil
        #
        # @note This is provided for backwards compatibility. New code should
        #   use {authenticate} which provides richer authentication metadata.
        #
        def extract_api_key(env)
          result = authenticate(env)
          result[:token] if result[:authenticated]
        end

        private

        # Attempts OAuth2 Bearer token authentication.
        #
        # Looks for Bearer tokens in the Authorization header and validates them
        # against the configured OAuth2 provider using token introspection.
        #
        # @param env [Hash] Rack environment hash
        #
        # @return [Hash, nil] Authentication result or nil if not OAuth2
        #
        # @see https://datatracker.ietf.org/doc/html/rfc6750#section-2.1 Bearer Token Usage
        #
        def try_oauth2_bearer(env)
          return nil unless OAuth2Config.enabled?

          auth = env["HTTP_AUTHORIZATION"].to_s.strip
          return nil if auth.empty?

          # RFC 6750: Bearer tokens in Authorization header
          # Format: "Bearer <access-token>"
          match = auth.match(/^Bearer\s+(.+)$/i)
          return nil unless match

          access_token = match[1].strip
          return nil if access_token.empty?

          # Validate token with OAuth2 provider
          token_info = OAuth2Config.validate_token(access_token)

          # If validation returns nil or inactive token, authentication fails
          # Return a failed result (not nil) to prevent fallback to API key auth
          # Once a Bearer token is provided, we don't fall back - it must be valid
          unless token_info && token_info["active"] == true
            return {
              authenticated: false,
              scheme: :oauth2,
              user: nil,
              token: nil,
              scopes: [],
              token_info: nil,
            }
          end

          # Extract scopes (space-separated per RFC 6749)
          scopes = (token_info["scope"] || "").split(/\s+/).reject(&:empty?)

          {
            authenticated: true,
            scheme: :oauth2,
            user: token_info["username"] || token_info["sub"] || token_info["client_id"],
            token: access_token,
            scopes: scopes,
            token_info: token_info,
          }
        end

        # Attempts API key authentication using various schemes.
        #
        # Tries multiple authentication methods for backwards compatibility:
        # - X-Api-Key header
        # - X-Rubygems-Api-Key header
        # - Authorization: Basic (username as key)
        # - Authorization: RubyGems (custom scheme)
        # - Authorization: Bearer (fallback if OAuth2 not configured)
        # - Raw Authorization header value
        #
        # @param env [Hash] Rack environment hash
        #
        # @return [Hash, nil] Authentication result or nil
        #
        def try_api_key_auth(env)
          # Try custom headers first (these take precedence)
          if (key = env["HTTP_X_API_KEY"].to_s.strip) && !key.empty?
            return build_api_key_result(key, :api_key)
          end

          if (key = env["HTTP_X_RUBYGEMS_API_KEY"].to_s.strip) && !key.empty?
            return build_api_key_result(key, :rubygems)
          end

          # Try Authorization header schemes
          auth = env["HTTP_AUTHORIZATION"].to_s.strip
          return nil if auth.empty?

          # HTTP Basic authentication (RFC 7617)
          # Format: "Basic <base64(username:password)>"
          # We use the username as the API key
          if (match = auth.match(/^Basic\s+(.+)$/i))
            encoded = match[1].strip
            # Validate that it's proper Base64 (only A-Z, a-z, 0-9, +, /, =)
            if encoded =~ /^[A-Za-z0-9+\/]+=*$/
              begin
                decoded = Base64.strict_decode64(encoded)
                # Extract username (before colon)
                username = decoded.include?(":") ? decoded.split(":", 2).first : decoded
                username = username.to_s.strip
                return build_api_key_result(username, :basic) unless username.empty?
              rescue ArgumentError
                # Invalid Base64 - return failed result
                return {
                  authenticated: false,
                  scheme: :basic,
                  user: nil,
                  token: nil,
                  scopes: [],
                  token_info: nil,
                }
              end
            else
              # Contains invalid Base64 characters - return failed result
              return {
                authenticated: false,
                scheme: :basic,
                user: nil,
                token: nil,
                scopes: [],
                token_info: nil,
              }
            end
          end

          # RubyGems custom scheme
          # Format: "RubyGems <api-key>"
          if (match = auth.match(/^RubyGems\s+(.+)$/i))
            key = match[1].to_s.strip
            return build_api_key_result(key, :rubygems) unless key.empty?
          end

          # Bearer without OAuth2 configured (treat as API key)
          # Format: "Bearer <api-key>"
          if (match = auth.match(/^Bearer\s+(.+)$/i))
            key = match[1].to_s.strip
            return build_api_key_result(key, :bearer) unless key.empty?
          end

          # Raw authorization header (backwards compatibility)
          # If there's no scheme and no spaces, treat as API key
          unless auth.include?(" ")
            return build_api_key_result(auth, :raw)
          end

          nil
        end

        # Builds an authentication result for API key schemes.
        #
        # @param key [String] The API key
        # @param scheme [Symbol] The authentication scheme used
        #
        # @return [Hash] Authentication result
        #
        def build_api_key_result(key, scheme)
          {
            authenticated: true,
            scheme: scheme,
            user: key,  # For API keys, the key itself is the user identifier
            token: key,
            scopes: [],  # API keys don't have scopes
            token_info: nil,
          }
        end
      end
    end
  end
end
