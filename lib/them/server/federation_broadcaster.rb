# frozen_string_literal: true

require "json"
require "uri"
require "net/http"
require "logger"
require_relative "../../../config/database"
require "them/server/crypto"

module Them
  module Server
    # Broadcasts gem publications to subscribed federated servers.
    #
    # This class implements the publisher side of the federation protocol, automatically
    # notifying subscribed peer servers when new gems are published. It ensures that
    # federated networks stay synchronized with minimal latency.
    #
    # The broadcaster implements patterns from:
    # - Publish-Subscribe messaging (WebSub, MQTT)
    # - Event-driven architecture
    # - Fan-out distribution patterns
    # - Resilient HTTP communication with retry logic
    #
    # @note Broadcasting is opt-in via ENV['FEDERATION_BROADCAST']=1 to prevent
    #   accidental network traffic in development/test environments.
    #
    # @see https://www.w3.org/TR/websub/ WebSub (W3C Recommendation)
    # @see https://datatracker.ietf.org/doc/html/rfc8030 Generic Event Delivery Using HTTP Push (RFC 8030)
    # @see https://mqtt.org/mqtt-specification/ MQTT Specification
    # @see https://www.enterpriseintegrationpatterns.com/patterns/messaging/PublishSubscribeChannel.html Pub-Sub Pattern
    #
    # @example Broadcasting a gem publication
    #   Them::Server::FederationBroadcaster.broadcast_gem(
    #     name: "rails",
    #     version: "7.0.0",
    #     scope_path: ["org", "rails"],
    #     file_path: "/path/to/rails-7.0.0.gem"
    #   )
    #
    class FederationBroadcaster
      # Logger instance for federation broadcaster operations
      LOGGER = Logger.new($stdout, progname: "FederationBroadcaster")

      class << self
        # Broadcasts a gem publication to all subscribed federated servers.
        #
        # This method performs the following operations:
        # 1. Checks if broadcasting is enabled (ENV['FEDERATION_BROADCAST']=1)
        # 2. Retrieves all subscribed servers from the database
        # 3. Computes the SHA-256 digest of the gem file for integrity verification
        # 4. Signs the gem metadata with this server's private key
        # 5. Sends signed push notifications to all subscribed servers in parallel
        #
        # The broadcast uses a fire-and-forget pattern with best-effort delivery.
        # Failed deliveries are logged but don't block the publication process.
        # Subscribers can later query this server to catch up on missed updates.
        #
        # @param name [String] The gem name
        # @param version [String] The gem version (must follow Semantic Versioning)
        # @param scope_path [Array<String>] The scope hierarchy (namespace path)
        # @param file_path [String] Absolute path to the gem file on disk
        #
        # @return [void]
        #
        # @note Broadcasting is disabled by default. Set ENV['FEDERATION_BROADCAST']=1
        #   to enable it in production.
        #
        # @note If no servers are subscribed, the method returns immediately without
        #   network activity.
        #
        # @note The gem file digest is computed using SHA-256 (RFC 6234) and serves
        #   as a content-addressable identifier, similar to Git commit hashes.
        #
        # @see https://semver.org/ Semantic Versioning
        # @see https://datatracker.ietf.org/doc/html/rfc6234 SHA-256 (RFC 6234)
        # @see https://git-scm.com/book/en/v2/Git-Internals-Git-Objects Content-Addressable Storage
        #
        # @example Broadcasting a scoped gem
        #   FederationBroadcaster.broadcast_gem(
        #     name: "activesupport",
        #     version: "7.0.0",
        #     scope_path: ["org", "rails"],
        #     file_path: "/gems/org/rails/activesupport-7.0.0.gem"
        #   )
        #
        # @example Broadcasting with environment variable
        #   ENV['FEDERATION_BROADCAST'] = '1'
        #   ENV['FEDERATION_BASE_URL'] = 'https://mygems.example.com'
        #   FederationBroadcaster.broadcast_gem(...)
        #
        def broadcast_gem(name:, version:, scope_path:, file_path:)
          # Early return if broadcasting is disabled
          return unless ENV["FEDERATION_BROADCAST"] == "1"

          db = Them::Server::Database.db

          # Retrieve all servers that have subscribed to this server's updates
          servers = db[:known_servers].where(subscribed: true).all
          return if servers.empty?

          # Compute content-addressable digest for integrity verification
          # This allows subscribers to verify the gem hasn't been tampered with
          digest_sha256 = begin
            bytes = File.binread(file_path)
            Them::Server::Crypto.sha256_hex(bytes)
          rescue StandardError => e
            LOGGER.warn("digest-failed: #{e.class}: #{e.message}")
            ""
          end

          # Sign the canonical gem record for non-repudiation
          # Format: "name\nversion\nscope\ndigest" (same as validation endpoints)
          record = [name, version, Array(scope_path).join("/"), digest_sha256].join("\n")
          record_sig_b64 = Them::Server::Crypto.sign_bytes(record)

          # Resolve this server's base URL for origin identification
          from_base_url = ENV["FEDERATION_BASE_URL"].to_s.strip
          from_base_url = autodetect_base_url if from_base_url.empty?

          # Fan-out broadcast to all subscribed servers
          # Each push is independent; failures don't affect other deliveries
          servers.each do |srv|
            endpoint = URI.join(srv[:base_url], "/federation/push").to_s
            payload = {
              from_base_url: from_base_url,
              name: name,
              version: version,
              scope_path: Array(scope_path),
              digest_sha256: digest_sha256,
              record_sig_b64: record_sig_b64,
              signed_at: Time.now.to_i,
            }

            # Best-effort delivery with retry
            with_retries("push", endpoint) do
              post_push(endpoint: endpoint, payload: payload)
            end
          end
        end

        private

        # Executes a block with automatic retry and exponential backoff.
        #
        # Implements the exponential backoff pattern for resilient HTTP communication.
        # Retries up to 3 times with delays of 0.5s, 1s, and 2s between attempts.
        # Unlike the client version, this swallows final errors to prevent blocking
        # the broadcast to other servers.
        #
        # @param action [String] Description of the action for logging
        # @param endpoint [String] The endpoint URL for logging
        #
        # @yield The block to execute (should return an HTTP response)
        # @yieldreturn [Net::HTTPResponse] HTTP response object
        #
        # @return [Net::HTTPResponse, nil] The successful response, or nil if all attempts fail
        #
        # @note Does not raise on final failure (fire-and-forget semantics)
        #
        # @see https://en.wikipedia.org/wiki/Exponential_backoff Exponential Backoff
        #
        def with_retries(action, endpoint)
          attempts = 0
          begin
            attempts += 1
            LOGGER.info("broadcast #{action} -> #{endpoint} attempt=#{attempts}")
            resp = yield
            if resp.respond_to?(:code) && resp.code.to_i >= 200 && resp.code.to_i < 300
              LOGGER.info("broadcast #{action} ok #{resp.code}")
              return resp
            else
              code = resp.respond_to?(:code) ? resp.code : "?"
              raise "HTTP #{code}"
            end
          rescue => e
            if attempts < 3
              # Exponential backoff: 0.5s, 1s, 2s
              sleep_time = 0.5 * (2 ** (attempts - 1))
              LOGGER.warn("broadcast #{action} error: #{e.class}: #{e.message}; retrying in #{sleep_time}s")
              sleep sleep_time
              retry
            else
              # Log error but don't raise (fire-and-forget pattern)
              LOGGER.error("broadcast #{action} failed after #{attempts} attempts: #{e.class}: #{e.message}")
            end
          end
        end

        # Posts a gem push notification to a federated server.
        #
        # This method constructs and signs the HTTP request for the /federation/push
        # endpoint, including both the payload signature and the HTTP request signature.
        #
        # @param endpoint [String] The full URL of the peer's /federation/push endpoint
        # @param payload [Hash] The gem metadata payload
        #
        # @return [Net::HTTPResponse] The HTTP response
        #
        # @note Includes dual signatures:
        #   1. payload.record_sig_b64: Signs the gem metadata itself
        #   2. X-Signature header: Signs the HTTP request (prevents MITM)
        #
        # @see https://datatracker.ietf.org/doc/html/draft-cavage-http-signatures HTTP Signatures
        #
        def post_push(endpoint:, payload:)
          uri = URI.parse(endpoint)
          body_str = JSON.generate(payload)
          body_digest = Them::Server::Crypto.sha256_hex(body_str)

          # Generate canonical HTTP request signature
          # This prevents man-in-the-middle tampering of the request
          canonical = Them::Server::Crypto.canonical_request_string(method: "POST", path: "/federation/push", signed_at: payload[:signed_at], body_digest: body_digest)
          signature = Them::Server::Crypto.sign_bytes(canonical)

          http = Net::HTTP.new(uri.host, uri.port)
          http.use_ssl = uri.scheme == "https"
          req = Net::HTTP::Post.new(uri.request_uri)
          req["Content-Type"] = "application/json"
          req["X-Signature"] = signature
          req.body = body_str
          http.request(req)
        end

        # Auto-detects this server's base URL as a fallback.
        #
        # This is a minimal fallback for development/testing. In production,
        # ENV['FEDERATION_BASE_URL'] should always be explicitly set to the
        # server's publicly accessible URL.
        #
        # @return [String] The auto-detected base URL
        #
        # @note Returns "http://localhost" which is only suitable for local testing.
        #   Production deployments MUST set ENV['FEDERATION_BASE_URL'].
        #
        def autodetect_base_url
          # Minimal fallback; recommend setting FEDERATION_BASE_URL
          "http://localhost"
        end
      end
    end
  end
end
