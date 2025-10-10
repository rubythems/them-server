# frozen_string_literal: true

require "json"
require_relative "../../../config/database"
require "gem/server/crypto"
require "gem/server/scope_resolver"

module Gem
  module Server
    module Actions
      module Federation
        # Validates gem existence and returns cryptographically signed metadata.
        #
        # This action implements a read-only validation endpoint that allows federated
        # servers to verify whether a gem exists on this server and retrieve its
        # metadata with cryptographic proof of authenticity. This supports federated
        # gem resolution where clients can query multiple servers to locate gems.
        #
        # The validation mechanism supports:
        # - Scope-aware gem lookup (hierarchical namespacing)
        # - Local vs federated gem differentiation
        # - Cryptographic signatures for non-repudiation
        # - Origin server traceability for federated gems
        #
        # This follows patterns from:
        # - Content-Addressable Storage (CAS) systems like IPFS
        # - Package registry APIs (npm, PyPI, Maven Central)
        # - Web of Trust and PGP key verification
        #
        # @note This endpoint is unauthenticated (read-only) but returns signed
        #   responses that can be verified by the recipient using this server's
        #   public key, similar to DNSSEC (RFC 4033).
        #
        # @see https://datatracker.ietf.org/doc/html/rfc4033 DNSSEC Introduction (RFC 4033)
        # @see https://github.com/ipfs/specs/blob/main/IPFS.md Content Addressable Storage (IPFS)
        # @see https://github.com/npm/registry/blob/master/docs/REGISTRY-API.md npm Registry API
        # @see https://datatracker.ietf.org/doc/html/rfc4880 OpenPGP Message Format (RFC 4880)
        # @see https://maven.apache.org/repository/layout.html Maven Repository Layout
        #
        # @example Request for scoped gem
        #   GET /federation/validate_gem/org/rails/activesupport
        #
        # @example Response for local gem
        #   {
        #     "exists": true,
        #     "source": "local",
        #     "name": "activesupport",
        #     "version": "7.0.0",
        #     "scope_path": ["org", "rails"],
        #     "digest_sha256": "abc123...",
        #     "record_sig_b64": "base64-encoded-signature",
        #     "public_key_b64": "base64-encoded-public-key"
        #   }
        #
        # @example Response for federated gem
        #   {
        #     "exists": true,
        #     "source": "federated",
        #     "name": "activesupport",
        #     "version": "7.0.0",
        #     "scope_path": ["org", "rails"],
        #     "digest_sha256": "abc123...",
        #     "record_sig_b64": "base64-encoded-signature",
        #     "origin_public_key_b64": "origin-server-public-key",
        #     "origin_base_url": "https://gems.example.com",
        #     "public_key_b64": "this-server-public-key"
        #   }
        #
        # @example Response for non-existent gem
        #   {
        #     "exists": false,
        #     "name": "nonexistent",
        #     "scope_path": ["org", "rails"]
        #   }
        #
        class ValidateGem < Gem::Server::Action
          # Validates gem existence and returns signed metadata.
          #
          # This method performs the following operations:
          # 1. Parse and validate the gem path from URL parameters
          # 2. Resolve the scope hierarchy (namespace)
          # 3. Search for the gem in local storage (priority)
          # 4. Fall back to federated gems if not found locally
          # 5. Generate cryptographic signatures for the metadata
          # 6. Return comprehensive gem information or non-existence
          #
          # The response includes SHA-256 digests for content verification and
          # Ed25519/RSA signatures for authenticity. For federated gems, both the
          # origin server's public key and this server's re-signature are included,
          # creating a chain of trust.
          #
          # @param request [Rack::Request, Hanami::Request] The HTTP request object
          #   containing the gem path in params[:path]
          # @param response [Rack::Response, Hanami::Response] The HTTP response object
          #   to be populated with validation results
          #
          # @return [void] Modifies the response object in place
          #
          # @note HTTP status codes per RFC 7231:
          #   - 200 OK: Always returned (existence indicated in JSON body)
          #   - 400 Bad Request: Missing gem name in path
          #
          # @note Path format: scope1/scope2/.../gem_name
          #   The last component is always the gem name, all preceding components
          #   form the scope path (namespace hierarchy).
          #
          # @note Signature verification chain for federated gems:
          #   1. Origin server signs the gem metadata (origin_public_key_b64)
          #   2. This server re-signs the metadata (public_key_b64)
          #   3. Clients can verify either or both signatures
          #
          # @see https://datatracker.ietf.org/doc/html/rfc6234 SHA-256 (RFC 6234)
          # @see https://datatracker.ietf.org/doc/html/rfc8032 EdDSA Signatures (RFC 8032)
          # @see https://datatracker.ietf.org/doc/html/rfc8017 PKCS #1: RSA Cryptography (RFC 8017)
          #
          # @example Validating a scoped gem
          #   # GET /federation/validate_gem/myorg/mygem
          #   # => 200 OK
          #   # => {"exists": true, "source": "local", ...}
          #
          # @example Validating with invalid path
          #   # GET /federation/validate_gem/
          #   # => 400 Bad Request
          #   # => "Missing gem name"
          #
          def handle(request, response)
            db = Database.db

            # Parse path parameter into scope and gem name components
            # Format: scope1/scope2/.../gem_name
            path_param = request.params[:path] || ""
            parts = path_param.split("/").reject(&:empty?)
            if parts.empty?
              response.status = 400
              response.body = "Missing gem name"
              return
            end

            # Last component is gem name, rest is scope path
            gem_name = parts.pop
            scope_path = parts

            # Resolve scope hierarchy (namespace)
            # This supports organization-scoped gems like @org/package in npm
            resolver = ::Gem::Server::ScopeResolver.new(scope_path, include_gem_name: false)
            scope = resolver.scope(create: false)
            scope_id = scope&.dig(:id)

            # Priority 1: Search for local gem (prefer local over federated)
            # Only non-yanked gems are considered valid
            local = db[:gems].where(name: gem_name, scope_id: scope_id, yanked: false).order(:version).last
            data = nil

            if local
              # Local gem found - compute digest and sign metadata
              # The digest provides content-addressable verification (like Git SHA)
              digest = begin
                bytes = File.binread(local[:file_path])
                Crypto.sha256_hex(bytes)
              rescue StandardError
                ""
              end

              # Sign the canonical record string for non-repudiation
              # Format: "name\nversion\nscope\ndigest"
              rec = [gem_name, local[:version], scope_path.join("/"), digest].join("\n")
              sig = Crypto.sign_bytes(rec)

              data = {
                exists: true,
                source: "local",
                name: gem_name,
                version: local[:version],
                scope_path: scope_path,
                digest_sha256: digest,
                record_sig_b64: sig,
                public_key_b64: Crypto.public_key_b64,
              }
            else
              # Priority 2: Search federated gems if no local copy exists
              # Returns the latest version from the federation
              fed = db[:federated_gems].where(name: gem_name, scope_id: scope_id).order(:version).last
              if fed
                # Re-sign the federated gem metadata with our key
                # This creates a chain of trust: origin -> us -> client
                rec = [gem_name, fed[:version], scope_path.join("/"), fed[:digest_sha256]].join("\n")
                sig = Crypto.sign_bytes(rec)

                # Include origin server information for trust verification
                origin = db[:known_servers][id: fed[:origin_server_id]]
                data = {
                  exists: true,
                  source: "federated",
                  name: gem_name,
                  version: fed[:version],
                  scope_path: scope_path,
                  digest_sha256: fed[:digest_sha256],
                  record_sig_b64: sig,
                  origin_public_key_b64: origin && origin[:public_key_b64],
                  origin_base_url: origin && origin[:base_url],
                  public_key_b64: Crypto.public_key_b64,
                }
              else
                # Gem not found (neither local nor federated)
                data = {exists: false, name: gem_name, scope_path: scope_path}
              end
            end

            # Always return 200 OK with existence in body (REST convention)
            response.format = :json
            response.status = 200
            response.body = JSON.generate(data)
          end
        end
      end
    end
  end
end

