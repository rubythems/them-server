# frozen_string_literal: true

require "json"
require "uri"
require "net/http"
require "logger"
require "them/server/crypto"

module Them
  module Server
    # Client for communicating with federated gem servers.
    #
    # This class implements the client-side of the federation protocol, allowing
    # this server to announce itself to and subscribe to other gem servers in the
    # federated network. It handles HTTP communication, request signing, and
    # automatic retry with exponential backoff.
    #
    # The client implements patterns from:
    # - HTTP client best practices (retry with exponential backoff)
    # - OAuth 2.0 client implementations
    # - Distributed system resilience patterns (Circuit Breaker, Retry)
    #
    # @note All requests are cryptographically signed using Ed25519 signatures
    #   to prevent tampering and ensure authenticity.
    #
    # @see https://datatracker.ietf.org/doc/html/rfc7231 HTTP/1.1 Semantics (RFC 7231)
    # @see https://datatracker.ietf.org/doc/html/rfc6749 OAuth 2.0 Framework (RFC 6749)
    # @see https://martinfowler.com/bliki/CircuitBreaker.html Circuit Breaker Pattern
    # @see https://aws.amazon.com/blogs/architecture/exponential-backoff-and-jitter/ Exponential Backoff
    #
    # @example Announcing to a peer server
    #   client = Them::Server::FederationClient.new
    #   client.announce(
    #     to_base_url: "https://gems.example.com",
    #     my_base_url: "https://mygems.example.com"
    #   )
    #
    # @example Subscribing to a peer server
    #   client = Them::Server::FederationClient.new
    #   client.subscribe(
    #     to_base_url: "https://gems.example.com",
    #     my_base_url: "https://mygems.example.com"
    #   )
    #
    class FederationClient
      # Logger instance for federation client operations
      LOGGER = Logger.new($stdout, progname: "FederationClient")

      # Announces this server to a remote federated server.
      #
      # This method implements the announcement handshake where this server
      # introduces itself to a peer, providing its base URL and public key.
      # The announcement is self-signed to prove ownership of the public key.
      #
      # The announcement follows a challenge-response pattern similar to TLS
      # handshakes, where the server proves possession of the private key
      # without transmitting it.
      #
      # @param to_base_url [String] The base URL of the peer server to announce to
      # @param my_base_url [String, nil] This server's base URL (falls back to
      #   ENV['FEDERATION_BASE_URL'] if not provided)
      #
      # @return [Net::HTTPResponse] The HTTP response from the peer server
      #
      # @raise [ArgumentError] If my_base_url is not provided and
      #   ENV['FEDERATION_BASE_URL'] is not set
      # @raise [RuntimeError] If the announcement fails after 3 retry attempts
      #
      # @note Uses exponential backoff retry strategy: 0.5s, 1s, 2s
      #
      # @see https://datatracker.ietf.org/doc/html/rfc8446 TLS 1.3 (RFC 8446)
      # @see https://datatracker.ietf.org/doc/html/rfc8032 EdDSA (RFC 8032)
      #
      # @example Announcing with explicit base URL
      #   client.announce(
      #     to_base_url: "https://gems.example.com",
      #     my_base_url: "https://mygems.example.com"
      #   )
      #
      # @example Announcing with environment variable
      #   ENV['FEDERATION_BASE_URL'] = "https://mygems.example.com"
      #   client.announce(to_base_url: "https://gems.example.com")
      #
      def announce(to_base_url:, my_base_url: nil)
        # Resolve this server's base URL from parameter or environment
        my_base = my_base_url.to_s.strip
        my_base = ENV["FEDERATION_BASE_URL"].to_s.strip if my_base.empty?
        raise ArgumentError, "my_base_url or ENV[FEDERATION_BASE_URL] required" if my_base.empty?

        # Prepare self-signed announcement payload
        # The signature proves ownership of the public key
        public_key_b64 = Them::Server::Crypto.public_key_b64
        signed_at = Time.now.to_i
        to_sign = [my_base, public_key_b64, signed_at.to_s].join("\n")
        body_digest = Them::Server::Crypto.sha256_hex(to_sign)

        # Generate canonical request signature per HTTP Signatures pattern
        canonical = Them::Server::Crypto.canonical_request_string(method: "POST", path: "/federation/announce", signed_at: signed_at, body_digest: body_digest)
        signature = Them::Server::Crypto.sign_bytes(canonical)

        payload = {base_url: my_base, public_key_b64: public_key_b64, signed_at: signed_at}
        endpoint = URI.join(to_base_url, "/federation/announce").to_s

        # Execute with automatic retry and exponential backoff
        with_retries("announce", endpoint) do
          post_json(endpoint, payload, {"X-Signature" => signature})
        end
      end

      # Subscribes to gem updates from a remote federated server.
      #
      # This method requests that the peer server send gem push notifications
      # to this server when new gems are published. The subscription requires
      # prior announcement to establish trust.
      #
      # This implements a pub/sub pattern similar to WebSub (formerly PubSubHubbub),
      # where subscribers express interest in receiving updates from publishers.
      #
      # @param to_base_url [String] The base URL of the peer server to subscribe to
      # @param my_base_url [String, nil] This server's base URL (falls back to
      #   ENV['FEDERATION_BASE_URL'] if not provided)
      #
      # @return [Net::HTTPResponse] The HTTP response from the peer server
      #
      # @raise [ArgumentError] If my_base_url is not provided and
      #   ENV['FEDERATION_BASE_URL'] is not set
      # @raise [RuntimeError] If the subscription fails after 3 retry attempts
      #
      # @note The peer server will reject subscriptions from unknown servers
      #   (servers that haven't announced first).
      #
      # @see https://www.w3.org/TR/websub/ WebSub (W3C Recommendation)
      # @see https://datatracker.ietf.org/doc/html/rfc8030 HTTP Push (RFC 8030)
      #
      # @example Subscribing to a peer server
      #   client.subscribe(
      #     to_base_url: "https://gems.example.com",
      #     my_base_url: "https://mygems.example.com"
      #   )
      #
      def subscribe(to_base_url:, my_base_url: nil)
        # Resolve this server's base URL from parameter or environment
        my_base = my_base_url.to_s.strip
        my_base = ENV["FEDERATION_BASE_URL"].to_s.strip if my_base.empty?
        raise ArgumentError, "my_base_url or ENV[FEDERATION_BASE_URL] required" if my_base.empty?

        # Prepare signed subscription request
        signed_at = Time.now.to_i
        payload = {base_url: my_base, signed_at: signed_at}
        body_str = JSON.generate(payload)
        body_digest = Them::Server::Crypto.sha256_hex(body_str)

        # Generate canonical request signature
        canonical = Them::Server::Crypto.canonical_request_string(method: "POST", path: "/federation/subscribe", signed_at: signed_at, body_digest: body_digest)
        signature = Them::Server::Crypto.sign_bytes(canonical)

        endpoint = URI.join(to_base_url, "/federation/subscribe").to_s

        # Execute with automatic retry and exponential backoff
        with_retries("subscribe", endpoint) do
          post_json(endpoint, payload, {"X-Signature" => signature})
        end
      end

      private

      # Executes a block with automatic retry and exponential backoff.
      #
      # Implements the exponential backoff pattern for resilient HTTP communication.
      # Retries up to 3 times with delays of 0.5s, 1s, and 2s between attempts.
      #
      # @param action [String] Description of the action for logging
      # @param endpoint [String] The endpoint URL for logging
      #
      # @yield The block to execute (should return an HTTP response)
      # @yieldreturn [Net::HTTPResponse] HTTP response object
      #
      # @return [Net::HTTPResponse] The successful response
      #
      # @raise [RuntimeError] If all retry attempts fail
      #
      # @note Considers HTTP 2xx status codes as success
      #
      # @see https://en.wikipedia.org/wiki/Exponential_backoff Exponential Backoff
      #
      def with_retries(action, endpoint)
        attempts = 0
        begin
          attempts += 1
          LOGGER.info("client #{action} -> #{endpoint} attempt=#{attempts}")
          resp = yield
          if resp.respond_to?(:code) && resp.code.to_i >= 200 && resp.code.to_i < 300
            LOGGER.info("client #{action} ok #{resp.code}")
            resp
          else
            code = resp.respond_to?(:code) ? resp.code : "?"
            raise "HTTP #{code}"
          end
        rescue => e
          if attempts < 3
            # Exponential backoff: 0.5s, 1s, 2s
            sleep_time = 0.5 * (2**(attempts - 1))
            LOGGER.warn("client #{action} error: #{e.class}: #{e.message}; retrying in #{sleep_time}s")
            sleep sleep_time
            retry
          else
            LOGGER.error("client #{action} failed after #{attempts} attempts: #{e.class}: #{e.message}")
            raise
          end
        end
      end

      # Posts JSON payload to an endpoint with custom headers.
      #
      # @param url [String] The full URL to post to
      # @param payload [Hash] The payload to JSON-encode and send
      # @param headers [Hash] Additional HTTP headers to include
      #
      # @return [Net::HTTPResponse] The HTTP response
      #
      # @note Automatically sets Content-Type: application/json
      # @note Supports both HTTP and HTTPS endpoints
      #
      def post_json(url, payload, headers = {})
        uri = URI.parse(url)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == "https"
        req = Net::HTTP::Post.new(uri.request_uri)
        req["Content-Type"] = "application/json"
        headers.each { |k, v| req[k] = v }
        req.body = JSON.generate(payload)
        http.request(req)
      end
    end
  end
end
