# frozen_string_literal: true

require "json"
require_relative "../../../config/database"
require "them/server/crypto"

module Them
  module Server
    module Actions
      module Federation
        # Handles subscription requests from federated servers.
        #
        # This action implements the subscription mechanism that allows a remote server
        # to express interest in receiving gem updates from this server. Subscriptions
        # establish a bidirectional trust relationship where both servers have announced
        # and authenticated each other.
        #
        # The subscription model follows patterns from:
        # - ActivityPub Follow activity (W3C Recommendation)
        # - PubSubHubbub/WebSub (W3C Recommendation, RFC 8030)
        # - XMPP Presence Subscription (RFC 6121)
        #
        # @note Subscription requires prior announcement - the subscribing server must
        #   be in the known_servers registry before it can subscribe. This implements
        #   a two-phase handshake similar to TCP connection establishment.
        #
        # @see https://www.w3.org/TR/activitypub/#follow-activity-outbox Follow Activity (ActivityPub)
        # @see https://www.w3.org/TR/websub/ WebSub (W3C Recommendation)
        # @see https://datatracker.ietf.org/doc/html/rfc8030 Generic Event Delivery Using HTTP Push
        # @see https://datatracker.ietf.org/doc/html/rfc6121#section-3 XMPP Presence Subscription
        # @see https://datatracker.ietf.org/doc/html/rfc8259 JSON specification (RFC 8259)
        #
        # @example Expected JSON payload structure
        #   {
        #     "base_url": "https://gems.example.com",
        #     "signed_at": 1697123456,
        #     "signature_b64": "base64-encoded-signature"
        #   }
        #
        # @example Response on successful subscription
        #   {
        #     "status": "ok"
        #   }
        #
        class Subscribe < Them::Server::Action
          # Handles the subscription request with authentication.
          #
          # This method performs the following operations:
          # 1. JSON payload parsing and validation (RFC 8259)
          # 2. Server lookup in known_servers registry (must be pre-announced)
          # 3. HTTP signature verification using the server's registered public key
          # 4. Updates the server's subscription status to enabled
          #
          # The subscription mechanism implements opt-in federation - servers only
          # receive updates from servers they've explicitly subscribed to. This
          # provides control over network traffic and trust boundaries.
          #
          # @param request [Rack::Request, Hanami::Request] The HTTP request object
          #   containing the subscription payload and signature
          # @param response [Rack::Response, Hanami::Response] The HTTP response object
          #   to be populated with status
          #
          # @return [void] Modifies the response object in place
          #
          # @note HTTP status codes per RFC 7231:
          #   - 200 OK: Subscription activated successfully
          #   - 400 Bad Request: Invalid JSON or missing required fields
          #   - 401 Unauthorized: Invalid signature
          #   - 403 Forbidden: Server not in known_servers (must announce first)
          #
          # @note The subscription is idempotent - repeated subscribe requests
          #   simply update the last_seen timestamp. Servers can re-subscribe
          #   after disconnection without issues.
          #
          # @see https://datatracker.ietf.org/doc/html/rfc7231 HTTP Status Codes (RFC 7231)
          # @see https://datatracker.ietf.org/doc/html/draft-cavage-http-signatures HTTP Signatures
          #
          # @example Successful subscription
          #   # POST /federation/subscribe
          #   # => 200 OK
          #   # => {"status": "ok"}
          #
          # @example Subscription without prior announcement
          #   # POST /federation/subscribe (from unknown server)
          #   # => 403 Forbidden
          #   # => "Unknown server"
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

            # Extract subscription fields
            base_url = payload["base_url"].to_s.strip
            signed_at = (payload["signed_at"] || request.env["HTTP_X_SIGNED_AT"]).to_i
            signature_b64 = payload["signature_b64"] || request.env["HTTP_X_SIGNATURE"]

            # Validate required fields
            if base_url.empty? || signature_b64.to_s.empty? || signed_at <= 0
              response.status = 400
              response.body = "Missing required fields"
              return
            end

            # Lookup server in known_servers registry
            # Subscription requires prior announcement (two-phase handshake)
            server = db[:known_servers].where(base_url: base_url).first
            unless server
              response.status = 403
              response.body = "Unknown server"
              return
            end

            # Verify HTTP signature using the server's registered public key
            # This ensures the subscription request is authentic and authorized
            path = request.env["PATH_INFO"].to_s
            digest = Crypto.sha256_hex(body_str)
            canonical = Crypto.canonical_request_string(method: request.env["REQUEST_METHOD"], path: path, signed_at: signed_at, body_digest: digest)
            unless Crypto.verify_signature(canonical, signature_b64, public_key_b64: server[:public_key_b64])
              response.status = 401
              response.body = "Invalid signature"
              return
            end

            # Activate subscription with idempotent update semantics
            # Updates subscription status and activity timestamps
            db[:known_servers].where(id: server[:id]).update(
              subscribed: true,
              last_seen_at: now,
              updated_at: now
            )

            # Return success confirmation
            response.format = :json
            response.status = 200
            response.body = JSON.generate({status: "ok"})
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
            rescue
              # Some IO objects don't support rewind; continue anyway
            end
            io.read.to_s
          end
        end
      end
    end
  end
end
