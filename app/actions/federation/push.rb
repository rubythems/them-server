# frozen_string_literal: true

require "json"
require_relative "../../../config/database"
require "gem/server/crypto"
require "gem/server/scope_resolver"

module Gem
  module Server
    module Actions
      module Federation
        # Handles incoming federated gem push requests from other gem servers.
        #
        # This action implements a federated push protocol that allows trusted gem servers
        # to synchronize gem metadata across a distributed network. The protocol employs
        # cryptographic signatures to ensure authenticity and integrity of federated data.
        #
        # @note This implementation follows principles similar to ActivityPub federation
        #   (W3C Recommendation) and uses HTTP Signatures for request authentication.
        #
        # @see https://www.w3.org/TR/activitypub/ ActivityPub W3C Recommendation
        # @see https://datatracker.ietf.org/doc/html/draft-cavage-http-signatures HTTP Signatures (IETF Draft)
        # @see https://datatracker.ietf.org/doc/html/rfc6749 OAuth 2.0 (RFC 6749) - for authorization concepts
        # @see https://datatracker.ietf.org/doc/html/rfc7231#section-6.3.3 HTTP 202 Accepted (RFC 7231)
        # @see https://datatracker.ietf.org/doc/html/rfc8259 JSON specification (RFC 8259)
        #
        # @example Expected JSON payload structure
        #   {
        #     "from_base_url": "https://gems.example.com",
        #     "name": "rails",
        #     "version": "7.0.0",
        #     "scope_path": ["org", "rails"],
        #     "digest_sha256": "abc123...",
        #     "record_sig_b64": "base64-encoded-signature",
        #     "signed_at": 1697123456,
        #     "signature_b64": "base64-encoded-http-signature"
        #   }
        #
        # @example HTTP headers used for signature verification
        #   X-Signed-At: 1697123456
        #   X-Signature: base64-encoded-signature
        #
        class Push < Gem::Server::Action
          # Handles the federated push request with cryptographic verification.
          #
          # This method implements a multi-stage verification process:
          # 1. JSON payload parsing and validation (RFC 8259)
          # 2. Server authentication via known_servers registry
          # 3. HTTP request signature verification using canonical request format
          # 4. Record-level signature verification for data integrity
          # 5. Scope resolution and creation if necessary
          # 6. Atomic database insertion with duplicate handling
          #
          # The signature verification follows a pattern similar to AWS Signature Version 4
          # and HTTP Signatures draft specification, ensuring that:
          # - The request came from a known, trusted server
          # - The request hasn't been tampered with in transit (MITM protection)
          # - The gem metadata itself is cryptographically signed by the origin
          #
          # @param request [Rack::Request, Hanami::Request] The HTTP request object
          #   containing the federated push payload and signature headers
          # @param response [Rack::Response, Hanami::Response] The HTTP response object
          #   to be populated with status and body
          #
          # @return [void] Modifies the response object in place
          #
          # @note Uses HTTP status codes per RFC 7231:
          #   - 202 Accepted: Request accepted for processing
          #   - 400 Bad Request: Invalid JSON or missing required fields
          #   - 401 Unauthorized: Invalid HTTP signature
          #   - 403 Forbidden: Unknown/untrusted server
          #   - 422 Unprocessable Entity: Invalid record signature
          #
          # @see https://datatracker.ietf.org/doc/html/rfc7231#section-6.5 HTTP Status Codes (RFC 7231)
          # @see https://docs.aws.amazon.com/general/latest/gr/signature-version-4.html AWS Signature Version 4
          # @see https://datatracker.ietf.org/doc/html/rfc6234 SHA-256 hashing (RFC 6234)
          #
          # @example Successful federated push
          #   # POST /federation/push
          #   # => 202 Accepted
          #   # => {"status": "accepted"}
          #
          # @example Failed authentication
          #   # POST /federation/push (with invalid signature)
          #   # => 401 Unauthorized
          #   # => "Invalid signature"
          #
          def handle(request, response)
            db = Database.db
            body_str = safe_read_body(request)
            now = Time.now

            # Parse JSON payload per RFC 8259
            begin
              payload = JSON.parse(body_str)
            rescue JSON::ParserError
              response.status = 400
              response.body = "Invalid JSON"
              return
            end

            # Extract and normalize payload fields
            # These fields constitute the federated gem record metadata
            from_base_url = payload["from_base_url"].to_s.strip
            name = payload["name"].to_s.strip
            version = payload["version"].to_s.strip
            scope_path = Array(payload["scope_path"]).map { |s| s.to_s }.reject(&:empty?)
            digest_sha256 = payload["digest_sha256"].to_s.strip
            record_sig_b64 = payload["record_sig_b64"].to_s.strip

            # Signature metadata - can come from payload or HTTP headers
            # This follows the HTTP Signatures draft pattern
            signed_at = (payload["signed_at"] || request.env["HTTP_X_SIGNED_AT"]).to_i
            signature_b64 = payload["signature_b64"] || request.env["HTTP_X_SIGNATURE"]

            # Validate required fields per protocol specification
            if from_base_url.empty? || name.empty? || version.empty? || digest_sha256.empty? || record_sig_b64.empty? || signature_b64.to_s.empty? || signed_at <= 0
              response.status = 400
              response.body = "Missing required fields"
              return
            end

            # Authenticate the origin server via known_servers registry
            # This implements a trust-on-first-use (TOFU) model with pre-registered servers
            server = db[:known_servers].where(base_url: from_base_url).first
            unless server
              response.status = 403
              response.body = "Unknown server"
              return
            end

            # Phase 1: Verify HTTP-level signature
            # Constructs a canonical request string and verifies it against the signature
            # This ensures the HTTP request itself hasn't been tampered with
            # Similar to AWS Signature Version 4 canonical request format
            path = request.env["PATH_INFO"].to_s
            digest = Crypto.sha256_hex(body_str)
            canonical = Crypto.canonical_request_string(method: request.env["REQUEST_METHOD"], path: path, signed_at: signed_at, body_digest: digest)
            unless Crypto.verify_signature(canonical, signature_b64, public_key_b64: server[:public_key_b64])
              response.status = 401
              response.body = "Invalid signature"
              return
            end

            # Phase 2: Verify record-level signature
            # This ensures the gem metadata itself is cryptographically signed
            # Provides end-to-end integrity even if HTTP signature is valid
            # The record string format: "name\nversion\nscope\ndigest"
            scope_full = scope_path.join("/")
            record_string = [name, version, scope_full, digest_sha256].join("\n")
            unless Crypto.verify_signature(record_string, record_sig_b64, public_key_b64: server[:public_key_b64])
              response.status = 422
              response.body = "Invalid record signature"
              return
            end

            # Resolve or create scope hierarchy
            # Scopes provide namespace organization similar to Maven coordinates
            # or NPM scoped packages (@org/package)
            scope = nil
            if scope_path.any?
              resolver = ::Gem::Server::ScopeResolver.new(scope_path, include_gem_name: false)
              scope = resolver.scope(create: true)
            end

            # Upsert federated gem record with idempotent duplicate handling
            # Uses database-level uniqueness constraints for race condition safety
            origin_id = server[:id]
            begin
              existing = db[:federated_gems].where(name: name, version: version, scope_id: scope&.dig(:id), origin_server_id: origin_id).first
              if existing
                # Idempotent: ignore duplicate pushes
                # Future enhancement: could update metadata if needed
              else
                db[:federated_gems].insert(
                  name: name,
                  version: version,
                  scope_id: scope&.dig(:id),
                  origin_server_id: origin_id,
                  digest_sha256: digest_sha256,
                  signature_b64: record_sig_b64,
                  created_at: now,
                )
              end
            rescue Sequel::UniqueConstraintViolation
              # Race condition: another request created the record first
              # This is acceptable; the operation is idempotent
            end

            # Return 202 Accepted per RFC 7231 Section 6.3.3
            # Indicates the request has been accepted for processing
            # but processing may not be complete (async federation model)
            response.format = :json
            response.status = 202
            response.body = JSON.generate({status: "accepted"})
          end

          private

          # Safely reads the request body with error handling.
          #
          # This method attempts to rewind the IO stream before reading to ensure
          # the complete body is captured, even if it has been partially read.
          # The rewind operation is wrapped in exception handling because some
          # IO objects (like StringIO in certain configurations) may not support it.
          #
          # @param request [Rack::Request, Hanami::Request] The HTTP request object
          #
          # @return [String] The complete request body as a string, or empty string if unavailable
          #
          # @note This is important for signature verification where the exact body
          #   content must be hashed. Any alteration would invalidate the signature.
          #
          # @see https://datatracker.ietf.org/doc/html/rfc7230#section-3.3 HTTP Message Body (RFC 7230)
          #
          def safe_read_body(request)
            io = request.body
            begin
              io.rewind
            rescue StandardError
              # Some IO objects don't support rewind; continue anyway
            end
            io.read.to_s
          end
        end
      end
    end
  end
end

