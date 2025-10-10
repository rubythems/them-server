# frozen_string_literal: true

require "base64"
require "ed25519"

module Gem
  module Server
    # Cryptographic operations for federation security.
    #
    # This module provides the cryptographic primitives used throughout the federation
    # protocol, including key management, digital signatures, and content hashing.
    # It uses Ed25519 (EdDSA) for all signing operations, which provides excellent
    # security with small key sizes and fast verification.
    #
    # The module implements cryptographic patterns from:
    # - Ed25519 digital signatures (RFC 8032)
    # - Public key infrastructure (PKI)
    # - Content-addressable hashing (SHA-256)
    # - HTTP request signing (similar to AWS Signature Version 4)
    #
    # Security properties:
    # - 128-bit security level (equivalent to AES-128)
    # - Deterministic signatures (no random number generation needed)
    # - Small signatures (64 bytes) and public keys (32 bytes)
    # - Fast verification (~70k verifications per second)
    # - Resistant to timing attacks
    #
    # @note Keys are cached in process memory for performance. In production,
    #   set ENV['FEDERATION_PRIVATE_KEY_B64'] and ENV['FEDERATION_PUBLIC_KEY_B64']
    #   from a secure key management system (e.g., AWS KMS, HashiCorp Vault).
    #
    # @see https://datatracker.ietf.org/doc/html/rfc8032 EdDSA (RFC 8032)
    # @see https://datatracker.ietf.org/doc/html/rfc6234 SHA-256 (RFC 6234)
    # @see https://ed25519.cr.yp.to/ Ed25519 High-Speed High-Security Signatures
    # @see https://docs.aws.amazon.com/general/latest/gr/signature-version-4.html AWS Signature Version 4
    # @see https://datatracker.ietf.org/doc/html/rfc5280 X.509 PKI (RFC 5280)
    #
    # @example Signing and verifying data
    #   signature = Crypto.sign_bytes("hello world")
    #   public_key = Crypto.public_key_b64
    #   Crypto.verify_signature("hello world", signature, public_key_b64: public_key)
    #   # => true
    #
    # @example Generating a canonical request signature
    #   digest = Crypto.sha256_hex(request_body)
    #   canonical = Crypto.canonical_request_string(
    #     method: "POST",
    #     path: "/api/endpoint",
    #     signed_at: Time.now.to_i,
    #     body_digest: digest
    #   )
    #   signature = Crypto.sign_bytes(canonical)
    #
    module Crypto
      module_function

      # Returns a cached signing keypair for this process.
      #
      # This method implements lazy initialization of the Ed25519 keypair used for
      # all cryptographic operations. In production, keys should be loaded from
      # environment variables that are populated by a secure key management system.
      # In development/test, a random keypair is generated on first use.
      #
      # The keypair consists of:
      # - Signing key (private key): 32 bytes, used to create signatures
      # - Verify key (public key): 32 bytes, used to verify signatures
      #
      # @return [Array<Ed25519::SigningKey, Ed25519::VerifyKey>] Tuple of [signing_key, verify_key]
      #
      # @raise [RuntimeError] If the provided keys don't form a valid keypair
      #
      # @note The keypair is cached in an instance variable for the lifetime of
      #   the process. Key rotation requires process restart.
      #
      # @note In production, set:
      #   - ENV['FEDERATION_PRIVATE_KEY_B64']: Base64-encoded 32-byte signing key
      #   - ENV['FEDERATION_PUBLIC_KEY_B64']: Base64-encoded 32-byte verify key
      #
      # @see https://datatracker.ietf.org/doc/html/rfc8032#section-5.1.5 Ed25519 Key Generation
      #
      # @example Using environment variables (production)
      #   ENV['FEDERATION_PRIVATE_KEY_B64'] = Base64.strict_encode64(signing_key_bytes)
      #   ENV['FEDERATION_PUBLIC_KEY_B64'] = Base64.strict_encode64(verify_key_bytes)
      #   sk, pk = Crypto.keypair
      #
      # @example Auto-generation (development)
      #   # No environment variables set
      #   sk, pk = Crypto.keypair  # Generates random keypair
      #
      def keypair
        @keypair ||= begin
          priv_b64 = ENV["FEDERATION_PRIVATE_KEY_B64"]
          pub_b64 = ENV["FEDERATION_PUBLIC_KEY_B64"]

          if priv_b64 && pub_b64
            # Load and validate keys from environment (production mode)
            sk = Ed25519::SigningKey.new(Base64.strict_decode64(priv_b64))
            pk = Ed25519::VerifyKey.new(Base64.strict_decode64(pub_b64))
            raise "Keypair mismatch" unless sk.verify_key.to_bytes == pk.to_bytes
            [sk, pk]
          else
            # Generate ephemeral keypair (development/test mode)
            sk = Ed25519::SigningKey.generate
            pk = sk.verify_key
            @generated = true
            [sk, pk]
          end
        end
      end

      # Returns the public key as raw bytes.
      #
      # @return [String] 32-byte binary string containing the Ed25519 public key
      #
      # @note The raw bytes are suitable for cryptographic operations but not
      #   for transmission. Use {public_key_b64} for API responses.
      #
      def public_key_bytes
        keypair[1].to_bytes
      end

      # Returns the public key as a Base64-encoded string.
      #
      # This format is used in all federation API payloads and responses.
      # Base64 encoding ensures the binary key can be safely transmitted in
      # JSON and HTTP headers without encoding issues.
      #
      # @return [String] Base64-encoded public key (44 characters)
      #
      # @note Uses RFC 4648 strict encoding (no line breaks, standard alphabet)
      #
      # @see https://datatracker.ietf.org/doc/html/rfc4648 Base64 Encoding (RFC 4648)
      #
      # @example
      #   Crypto.public_key_b64
      #   # => "3q2+7w/y9kHlQ8nMx..."
      #
      def public_key_b64
        Base64.strict_encode64(public_key_bytes)
      end

      # Signs arbitrary data and returns the signature as Base64.
      #
      # This method creates an Ed25519 signature over the provided bytes using
      # this server's private key. Ed25519 signatures are deterministic, meaning
      # the same input always produces the same signature (no randomness needed).
      #
      # The signature provides:
      # - Authentication: Proves the signer possesses the private key
      # - Integrity: Detects any modification of the signed data
      # - Non-repudiation: Signer cannot deny creating the signature
      #
      # @param bytes [String] The data to sign (binary or text)
      #
      # @return [String] Base64-encoded signature (88 characters for Ed25519)
      #
      # @note Ed25519 signatures are always exactly 64 bytes (88 Base64 characters)
      #
      # @see https://datatracker.ietf.org/doc/html/rfc8032#section-5.1.6 Ed25519 Signing
      #
      # @example Signing a message
      #   signature = Crypto.sign_bytes("important message")
      #   # => "hQEMA+... (base64 signature)"
      #
      # @example Signing JSON for API requests
      #   payload = JSON.generate({name: "gem", version: "1.0"})
      #   signature = Crypto.sign_bytes(payload)
      #
      def sign_bytes(bytes)
        sk, _pk = keypair
        sig = sk.sign(bytes)
        Base64.strict_encode64(sig)
      end

      # Verifies a signature over data using a public key.
      #
      # This method verifies that the provided signature was created by the holder
      # of the private key corresponding to the given public key, and that the
      # signed data has not been modified.
      #
      # Constant-time comparison is used internally by the Ed25519 library to
      # prevent timing attacks that could leak information about the key.
      #
      # @param bytes [String] The data that was signed
      # @param signature_b64 [String] The Base64-encoded signature to verify
      # @param public_key_b64 [String, nil] Base64-encoded public key
      # @param public_key_bytes [String, nil] Raw binary public key
      #
      # @return [Boolean] true if signature is valid, false otherwise
      #
      # @raise [ArgumentError] If neither public_key_b64 nor public_key_bytes is provided
      #
      # @note Does not raise on invalid signatures; returns false instead.
      #   This prevents timing attacks based on exception handling.
      #
      # @see https://datatracker.ietf.org/doc/html/rfc8032#section-5.1.7 Ed25519 Verification
      # @see https://en.wikipedia.org/wiki/Timing_attack Timing Attacks
      #
      # @example Verifying a signature with Base64 key
      #   valid = Crypto.verify_signature(
      #     "message",
      #     signature_b64,
      #     public_key_b64: peer_public_key
      #   )
      #
      # @example Verifying with raw bytes
      #   valid = Crypto.verify_signature(
      #     "message",
      #     signature_b64,
      #     public_key_bytes: raw_key
      #   )
      #
      def verify_signature(bytes, signature_b64, public_key_b64: nil, public_key_bytes: nil)
        raise ArgumentError, "missing public key" unless public_key_b64 || public_key_bytes

        # Decode public key from Base64 if necessary
        pk_bytes = public_key_bytes || Base64.strict_decode64(public_key_b64)
        vk = Ed25519::VerifyKey.new(pk_bytes)

        # Verify signature (constant-time comparison)
        vk.verify(Base64.strict_decode64(signature_b64), bytes)
        true
      rescue Ed25519::VerifyError
        # Invalid signature - return false instead of raising
        false
      end

      # Builds a canonical string for HTTP request signing.
      #
      # This method constructs a deterministic string representation of an HTTP
      # request that can be signed to prove authenticity. The canonical format
      # includes all security-relevant components of the request in a fixed order.
      #
      # The canonical format follows patterns from AWS Signature Version 4 and
      # HTTP Signatures (IETF draft), including:
      # - HTTP method (prevents method confusion attacks)
      # - Request path (prevents path substitution)
      # - Timestamp (prevents replay attacks)
      # - Body digest (prevents body tampering)
      #
      # Components are newline-separated to prevent concatenation attacks where
      # "POST/api" + "123abc" could be confused with "POST" + "/api123" + "abc".
      #
      # @param method [String] HTTP method (e.g., "POST", "GET")
      # @param path [String] Request path (e.g., "/federation/push")
      # @param signed_at [Integer] Unix timestamp when the request was signed
      # @param body_digest [String] Hex-encoded SHA-256 digest of the request body
      #
      # @return [String] Canonical request string with newline separators
      #
      # @note The method is normalized to uppercase to prevent case-sensitivity issues
      #
      # @see https://docs.aws.amazon.com/general/latest/gr/sigv4-create-canonical-request.html AWS Canonical Request
      # @see https://datatracker.ietf.org/doc/html/draft-cavage-http-signatures-12 HTTP Signatures
      #
      # @example Creating a canonical request
      #   body = JSON.generate({name: "gem"})
      #   digest = Crypto.sha256_hex(body)
      #   canonical = Crypto.canonical_request_string(
      #     method: "POST",
      #     path: "/federation/push",
      #     signed_at: 1697123456,
      #     body_digest: digest
      #   )
      #   # => "POST\n/federation/push\n1697123456\nabc123..."
      #
      def canonical_request_string(method:, path:, signed_at:, body_digest:)
        [method.upcase, path, signed_at.to_i.to_s, body_digest].join("\n")
      end

      # Computes SHA-256 digest in hexadecimal format.
      #
      # This method provides content-addressable hashing for gem files and request
      # bodies. SHA-256 is a cryptographic hash function that produces a unique
      # 256-bit (32-byte) fingerprint for any input data.
      #
      # Properties of SHA-256:
      # - Deterministic: Same input always produces same hash
      # - One-way: Cannot recover input from hash
      # - Collision-resistant: Extremely unlikely for two inputs to produce same hash
      # - Avalanche effect: Small input change completely changes hash
      #
      # @param bytes [String] The data to hash (binary or text)
      #
      # @return [String] Hexadecimal digest (64 hex characters = 256 bits)
      #
      # @note Uses SHA-256 from Ruby's standard Digest library (OpenSSL-backed)
      #
      # @see https://datatracker.ietf.org/doc/html/rfc6234 SHA-256 (RFC 6234)
      # @see https://nvlpubs.nist.gov/nistpubs/FIPS/NIST.FIPS.180-4.pdf FIPS 180-4 Secure Hash Standard
      #
      # @example Hashing a file for integrity verification
      #   file_bytes = File.binread("rails-7.0.0.gem")
      #   digest = Crypto.sha256_hex(file_bytes)
      #   # => "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
      #
      # @example Hashing a request body
      #   body = JSON.generate({name: "gem", version: "1.0"})
      #   digest = Crypto.sha256_hex(body)
      #
      def sha256_hex(bytes)
        require "digest"
        Digest::SHA256.hexdigest(bytes)
      end
    end
  end
end

