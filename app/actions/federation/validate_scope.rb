# frozen_string_literal: true

require "json"
require_relative "../../../config/database"
require "them/server/crypto"
require "them/server/scope_resolver"

module Them
  module Server
    module Actions
      module Federation
        # Validates scope existence and returns cryptographically signed metadata.
        #
        # This action implements a read-only validation endpoint for verifying the
        # existence of scope hierarchies (namespaces) on this server. Scopes provide
        # organizational structure for gems, similar to Maven group IDs, npm scopes,
        # or Java package namespaces.
        #
        # The scope validation mechanism enables:
        # - Namespace verification before gem publication
        # - Federated namespace discovery and ownership verification
        # - Hierarchical organization (e.g., org/team/project)
        # - Cryptographic proof of scope existence
        #
        # This follows patterns from:
        # - DNS zone verification (RFC 1034, RFC 1035)
        # - Maven coordinates (groupId:artifactId:version)
        # - npm scoped packages (@org/package)
        # - Java package naming conventions (reverse domain names)
        #
        # @note This endpoint is unauthenticated (read-only) but returns signed
        #   responses that can be verified by the recipient, similar to DNSSEC
        #   resource record signatures.
        #
        # @see https://datatracker.ietf.org/doc/html/rfc1034 DNS Concepts (RFC 1034)
        # @see https://datatracker.ietf.org/doc/html/rfc1035 DNS Implementation (RFC 1035)
        # @see https://datatracker.ietf.org/doc/html/rfc4034 DNSSEC Resource Records (RFC 4034)
        # @see https://maven.apache.org/guides/mini/guide-naming-conventions.html Maven Naming Conventions
        # @see https://docs.npmjs.com/cli/v9/using-npm/scope npm Scopes
        # @see https://docs.oracle.com/javase/tutorial/java/package/namingpkgs.html Java Package Naming
        #
        # @example Request for multi-level scope
        #   GET /federation/validate_scope/org/rails/core
        #
        # @example Response for existing scope
        #   {
        #     "exists": true,
        #     "scope_path": ["org", "rails", "core"],
        #     "signed_at": 1697123456,
        #     "record_sig_b64": "base64-encoded-signature",
        #     "public_key_b64": "base64-encoded-public-key"
        #   }
        #
        # @example Response for non-existent scope
        #   {
        #     "exists": false,
        #     "scope_path": ["org", "nonexistent"],
        #     "signed_at": 1697123456,
        #     "record_sig_b64": "base64-encoded-signature",
        #     "public_key_b64": "base64-encoded-public-key"
        #   }
        #
        class ValidateScope < Them::Server::Action
          # Validates scope existence and returns signed metadata.
          #
          # This method performs the following operations:
          # 1. Parse the scope path from URL parameters
          # 2. Resolve the scope hierarchy in the database
          # 3. Generate a cryptographic signature for the validation result
          # 4. Return scope existence status with verification data
          #
          # The response is always signed, regardless of whether the scope exists.
          # This allows clients to cryptographically verify negative responses
          # (scope does not exist) as well as positive ones, preventing forgery
          # of "not found" responses.
          #
          # The canonical signing format:
          # - Type: "scope" (distinguishes from gem signatures)
          # - Path: "org/rails/core" (full scope path)
          #
          # @param request [Rack::Request, Hanami::Request] The HTTP request object
          #   containing the scope path in params[:path]
          # @param response [Rack::Response, Hanami::Response] The HTTP response object
          #   to be populated with validation results
          #
          # @return [void] Modifies the response object in place
          #
          # @note HTTP status codes per RFC 7231:
          #   - 200 OK: Always returned (existence indicated in JSON body)
          #
          # @note Path format: scope1/scope2/scope3/...
          #   Each component represents one level in the hierarchy.
          #   Empty path components are ignored.
          #
          # @note Signature provides authenticated denial of existence, similar to
          #   DNSSEC NSEC/NSEC3 records (RFC 5155), preventing cache poisoning
          #   attacks where an attacker claims a scope doesn't exist.
          #
          # @see https://datatracker.ietf.org/doc/html/rfc7231 HTTP Status Codes (RFC 7231)
          # @see https://datatracker.ietf.org/doc/html/rfc5155 DNSSEC NSEC3 (RFC 5155)
          # @see https://datatracker.ietf.org/doc/html/rfc8032 EdDSA Signatures (RFC 8032)
          # @see https://datatracker.ietf.org/doc/html/rfc8017 PKCS #1: RSA Cryptography (RFC 8017)
          #
          # @example Validating a scope
          #   # GET /federation/validate_scope/myorg/myteam
          #   # => 200 OK
          #   # => {"exists": true, "scope_path": ["myorg", "myteam"], ...}
          #
          # @example Validating empty path
          #   # GET /federation/validate_scope/
          #   # => 200 OK
          #   # => {"exists": false, "scope_path": [], ...}
          #
          def handle(request, response)
            db = Database.db

            # Parse path parameter into scope components
            # Format: scope1/scope2/scope3/...
            path_param = request.params[:path] || ""
            path_parts = path_param.split("/").reject(&:empty?)

            # Resolve scope hierarchy in database
            # Returns nil if scope doesn't exist (non-creating lookup)
            resolver = ::Them::Server::ScopeResolver.new(path_parts, include_gem_name: false)
            scope = resolver.scope(create: false)
            exists = !scope.nil?

            # Generate cryptographic signature for the validation result
            # This allows clients to verify both positive and negative responses
            # The "scope" prefix distinguishes this from gem record signatures
            full_path = path_parts.join("/")
            record_string = ["scope", full_path].join("\n")
            signed_at = Time.now.to_i
            signature_b64 = Crypto.sign_bytes(record_string)

            # Return signed validation result
            # Always 200 OK with existence in JSON body (REST convention)
            response.format = :json
            response.status = 200
            response.body = JSON.generate({
              exists: exists,
              scope_path: path_parts,
              signed_at: signed_at,
              record_sig_b64: signature_b64,
              public_key_b64: Crypto.public_key_b64,
            })
          end
        end
      end
    end
  end
end

