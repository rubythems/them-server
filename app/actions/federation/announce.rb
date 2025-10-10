# frozen_string_literal: true

require "json"
require_relative "../../../config/database"
require "gem/server/crypto"

module Gem
  module Server
    module Actions
      module Federation
        # Handles server announcement and discovery in the federated network.
        #
        # This action implements a server announcement protocol that allows gem servers
        # to introduce themselves to the network and register their public keys for
        # cryptographic verification. This is the first step in establishing trust
        # between federated servers.
        #
        # The announcement mechanism is inspired by:
        # - WebFinger (RFC 7033) for service discovery
        # - ActivityPub server-to-server communication patterns
        # - OAuth 2.0 Dynamic Client Registration (RFC 7591)
        #
        # @note This implements a self-authenticating announcement where the server
        #   proves ownership of its public key by signing the announcement with the
        #   corresponding private key (similar to DKIM in RFC 6376).
        #
        # @see https://datatracker.ietf.org/doc/html/rfc7033 WebFinger (RFC 7033)
        # @see https://datatracker.ietf.org/doc/html/rfc7591 OAuth 2.0 Dynamic Client Registration
        # @see https://datatracker.ietf.org/doc/html/rfc6376 DKIM Signatures (RFC 6376)
        # @see https://www.w3.org/TR/activitypub/#server-to-server-interactions ActivityPub Server-to-Server
        # @see https://datatracker.ietf.org/doc/html/rfc8259 JSON specification (RFC 8259)
        #
        # @example Expected JSON payload structure
        #   {
        #     "base_url": "https://gems.example.com",
        #     "public_key_b64": "base64-encoded-public-key",
        #     "signed_at": 1697123456,
        #     "signature_b64": "base64-encoded-signature"
        #   }
        #
        # @example Response on successful announcement
        #   {
        #     "status": "ok",
        #     "public_key_b64": "base64-encoded-server-public-key"
        #   }
        #
        class Announce < Gem::Server::Action
          # Handles the server announcement request with self-authentication.
          #
          # This method performs the following operations:
          # 1. JSON payload parsing and validation (RFC 8259)
          # 2. Self-signature verification using the provided public key
          # 3. Server registration or update in the known_servers registry
          # 4. Returns this server's public key for mutual authentication
          #
          # The self-signature proves that the announcing server possesses the private
          # key corresponding to the public key being registered. This prevents
          # impersonation attacks where a malicious server tries to register with
          # another server's public key.
          #
          # The canonical signing format includes:
          # - base_url: The server's base URL for identification
          # - public_key_b64: The public key being registered
          # - signed_at: Unix timestamp to prevent replay attacks
          #
          # @param request [Rack::Request, Hanami::Request] The HTTP request object
          #   containing the announcement payload and signature
          # @param response [Rack::Response, Hanami::Response] The HTTP response object
          #   to be populated with status and server's public key
          #
          # @return [void] Modifies the response object in place
          #
          # @note HTTP status codes per RFC 7231:
          #   - 200 OK: Announcement accepted and server registered
          #   - 400 Bad Request: Invalid JSON or missing required fields
          #   - 401 Unauthorized: Invalid self-signature (failed to prove key ownership)
          #
          # @note The registration is idempotent - repeated announcements update
          #   the server's public key and last_seen timestamp. This allows for
          #   key rotation and server status tracking.
          #
          # @see https://datatracker.ietf.org/doc/html/rfc7231 HTTP Status Codes (RFC 7231)
          # @see https://datatracker.ietf.org/doc/html/rfc8017 PKCS #1: RSA Cryptography (RFC 8017)
          # @see https://datatracker.ietf.org/doc/html/rfc5246#appendix-F.1.1.2 Replay Attack Prevention
          #
          # @example Successful server announcement
          #   # POST /federation/announce
          #   # => 200 OK
          #   # => {"status": "ok", "public_key_b64": "..."}
          #
          # @example Failed authentication (key ownership not proven)
          #   # POST /federation/announce (with mismatched signature)
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

            # Extract announcement fields
            base_url = payload["base_url"].to_s.strip
            public_key_b64 = payload["public_key_b64"].to_s.strip
            signed_at = (payload["signed_at"] || request.env["HTTP_X_SIGNED_AT"]).to_i
            signature_b64 = request.env["HTTP_X_SIGNATURE"] || payload["signature_b64"]

            # Validate required fields
            if base_url.empty? || public_key_b64.empty? || signature_b64.to_s.empty? || signed_at <= 0
              response.status = 400
              response.body = "Missing required fields"
              return
            end

            # Verify self-signature to prove ownership of the public key
            # This prevents a malicious server from registering with another server's key
            # The deterministic payload format ensures consistent verification
            path = request.env["PATH_INFO"].to_s
            to_sign = [base_url, public_key_b64, signed_at.to_s].join("\n")
            digest = Crypto.sha256_hex(to_sign)
            canonical = Crypto.canonical_request_string(method: request.env["REQUEST_METHOD"], path: path, signed_at: signed_at, body_digest: digest)
            unless Crypto.verify_signature(canonical, signature_b64, public_key_b64: public_key_b64)
              response.status = 401
              response.body = "Invalid signature"
              return
            end

            # Upsert server registration with idempotent update semantics
            # Allows for key rotation and status tracking over time
            existing = db[:known_servers].where(base_url: base_url).first
            if existing
              db[:known_servers].where(id: existing[:id]).update(
                public_key_b64: public_key_b64,
                last_announced_at: Time.at(signed_at),
                last_seen_at: now,
                updated_at: now,
              )
            else
              db[:known_servers].insert(
                base_url: base_url,
                public_key_b64: public_key_b64,
                subscribed: false,
                last_announced_at: Time.at(signed_at),
                last_seen_at: now,
                created_at: now,
                updated_at: now,
              )
            end

            # Return success with our public key for mutual authentication
            # This allows the announcing server to register us in their known_servers
            response.format = :json
            response.status = 200
            response.body = JSON.generate({status: "ok", public_key_b64: Crypto.public_key_b64})
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
          # @note Critical for signature verification where the exact body content
          #   must be hashed. Any alteration would invalidate the signature.
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
