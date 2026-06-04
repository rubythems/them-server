# Product Requirements Document (PRD) for Federated Ruby Them Server

## Overview

This PRD outlines the requirements for a Ruby gem server that supports scoped gem namespaces, permissions management, federation across multiple instances, and a key server for cryptographic validation. The server must be backward-compatible with existing RubyGems conventions, allowing it to serve as a drop-in replacement or extension to rubygems.org.

## 1. Scopes (Namespaces)

### Description
Scopes allow for the organization of gems into logical namespaces, enabling the reuse of gem names across different scopes on the same server. This prevents naming conflicts and provides better organization for large-scale gem ecosystems.

### Requirements
- Clients must be able to specify a scope when pushing or pulling gems.
- A gem name can be reused across different scopes (e.g., `mygem` in scope `org1` and `org2`).
- The null scope (empty or default) is treated as the root scope, equivalent to the global namespace in traditional RubyGems.
- Scope names must be URL-safe strings, allowing them to be used in API endpoints (e.g., `/{scope-path}/{gem}` where scope-path can include up to 3 levels of nested scopes separated by `/`).
- Scopes must be discoverable via API endpoints.

### API Considerations
- Push endpoint: `POST /{scope-path}` (scope-path is the full scope hierarchy, e.g., `/org/sub`)
- Pull endpoint: `GET /{scope-path}/{gem}`
- List gems in scope: `GET /{scope-path}`

## 2. Permissions

### Description
Permissions control who can push, yank, or manage gems and scopes. This includes hierarchical ownership where scope owners have higher-level control.

### Requirements
- **Gem Owners**: Each gem has a set of owners with push/yank rights. Owners can push new versions and yank existing ones for their gems.
- **Scope Owners**: Each scope has a set of authorized owners. Scope owners can add or remove gem push rights from gem owners within their scope.
- Hierarchy: Scope owners exist at a higher level than gem owners. Scope owners can override gem-level permissions.
- Authentication: All operations requiring permissions must use cryptographic signatures or API keys tied to verified identities.
- Authorization checks must occur on push, yank, and management operations.

### API Considerations
- Add gem owner: `POST /{scope-path}/{gem}/owners` (scope owner only)
- Remove gem owner: `DELETE /{scope-path}/{gem}/owners/{owner}` (scope owner only)
- Yank gem: `DELETE /{scope-path}/{gem}/versions/{version}` (gem owner only)

## 3. Federation

### Description
Federation allows multiple instances of the gem server to operate across different domains, sharing gem updates, scopes, and validation information in a decentralized manner.

### Requirements
- **Protocol Selection**: Use or extend an existing federation protocol. Recommended: AT Protocol (ATProto) due to its focus on decentralized social networks and content distribution. If ATProto is insufficient, consider ActivityPub or a custom protocol based on DID (Decentralized Identifiers) and verifiable credentials.
- **Discovery**: Servers must be able to discover other federated servers via a registry or DHT (Distributed Hash Table).
- **Subscription and Updates**: Servers can subscribe to gem updates from other servers and push updates to subscribers.
- **Validation**:
  - Equivalency of signing keys for gems.
  - Presence and validity of scopes (cryptographically signed).
  - Presence and validity of gem names within scopes (signed).
- **Publishing**:
  - New scopes: Published with cryptographic signature, verifiable via public key.
  - New gems: Signed and verifiable.
- **Protocol Requirements**:
  - Decentralized: No central authority.
  - Secure: All communications encrypted and signed.
  - Efficient: Support for delta updates and caching.
  - Extensible: Allow for future features like gem dependencies federation.
  - Reuse: Extend ATProto by defining custom record types for gems, scopes, and keys. If extending, add schemas for GemRecord, ScopeRecord, KeyRecord.

### API Considerations
- Federation endpoints for subscribing: `POST /federation/subscribe`
- Push updates: `POST /federation/push`
- Validate scope: `GET /federation/validate/scope/{scope-path}`
- Validate gem: `GET /federation/validate/gem/{scope-path}/{gem}`

## 4. Key Server

### Description
The key server manages public keys for gem owners, enabling cryptographic validation of gem signatures.

### Requirements
- **Public Keys**: Every gem owner must have a published public key for validating pushed gems.
- **API**: Provide endpoints to retrieve and validate keys.
- **Signing**: First push of a gem must be signed with the owner's private key. Public key must be made available to the federation.
- **Standards and Protocols**:
  - Support RubyGems signing standards (e.g., PGP, Ed25519 as per RubyGems 3.2+).
  - Minimum: Ed25519 for signatures.
  - Additional: Support for RSA, ECDSA if needed for compatibility.
- **Revocation**: Support key revocation via a revocation list or certificate revocation. Owners can revoke keys, and revocations must propagate through federation.
- **Validation**: API to check key validity, including revocation status.
- **Storage**: Keys stored securely, possibly in a distributed manner via federation.

### API Considerations
- Get key: `GET /keys/{owner}`
- Validate key: `POST /keys/validate` (with signature proof)
- Revoke key: `POST /keys/revoke` (owner only)

## 5. Backward Compatibility with RubyGems

### Description
The server must decompose to existing RubyGems conventions, allowing it to serve existing gems and integrate with the broader ecosystem.

### Requirements
- **Default Source**: Default to `https://rubygems.org` for unspecified sources.
- **Null Scope**: Treat null scope as the root, mapping to traditional gem names.
- **Mirroring**: Ability to mirror unsigned gems from other servers (e.g., rubygems.org) that don't support federation.
- **Installation**: Clients can install existing corpus of gems without modification.
- **API Compatibility**: Support standard RubyGems API endpoints (e.g., `/gems`, `/api/v1/gems`) for backward compatibility.
- **Migration**: Provide tools to migrate existing gems into scopes if desired.

### API Considerations
- Standard endpoints: `GET /gems` (maps to null scope)
- Mirror endpoint: `POST /admin/mirror` (internal for syncing from rubygems.org)

## Implementation Considerations

- **Security**: All sensitive operations must use HTTPS, signatures, and possibly OAuth or similar for authentication.
- **Scalability**: Design for high availability, possibly using distributed databases.
- **Testing**: Comprehensive tests for federation, permissions, and compatibility.
- **Documentation**: API docs, federation protocol specs.
- **Timeline**: Phase 1: Basic server with scopes and permissions. Phase 2: Federation. Phase 3: Full key server and compatibility.

## Risks and Mitigations

- **Adoption**: Low adoption of federation; mitigate by ensuring backward compatibility.
- **Security**: Key compromises; mitigate with revocation and multi-signature requirements.
- **Complexity**: Federation protocol; mitigate by choosing/extending proven protocols like ATProto.
