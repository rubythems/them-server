# Phase 2: Federation Implementation

## Overview
This phase adds federation capabilities, allowing multiple gem server instances to communicate, share updates, and validate across domains. It builds on the basic server from Phase 1 by integrating a federation protocol for decentralized gem distribution.

## Objectives
- Implement federation protocol (e.g., extend ATProto).
- Enable server discovery and subscription to updates.
- Support validation of scopes and gems across servers.
- Ensure secure, signed communications.

## Steps

### 1. Choose and Integrate Federation Protocol
- Evaluate ATProto for suitability; if not, select alternative (e.g., ActivityPub).
- Add protocol libraries to the project (e.g., atproto gem if available, or custom implementation).
- Define custom record types: GemRecord, ScopeRecord, KeyRecord.
- Set up protocol client/server components in the app.

### 2. Server Discovery Mechanism
- Implement registry or DHT for discovering federated servers.
- Add endpoint for publishing server info: `POST /federation/announce`.
- Client logic to query registry and maintain list of known servers.

### 3. Subscription and Update Propagation
- Add subscription endpoint: `POST /federation/subscribe` to follow another server.
- Implement push updates: `POST /federation/push` to send gem/scope updates to subscribers.
- Handle incoming updates: validate and store federated gems/scopes.
- Support delta updates for efficiency.

### 4. Validation Endpoints
- Implement validate scope: `GET /federation/validate/scope/{scope-path}` checks presence and signature.
- Implement validate gem: `GET /federation/validate/gem/{scope-path}/{gem}` verifies gem authenticity.
- Integrate with key validation for signatures.

### 5. Publishing New Scopes and Gems
- When a new scope is created, publish via federation with signature.
- For new gems, sign and broadcast to subscribers.
- Ensure propagation respects permissions (e.g., only authorized servers receive updates).

### 6. Security and Encryption
- All federation communications must be encrypted and signed.
- Implement mutual authentication between servers.
- Handle key equivalency checks for cross-server validation.

### 7. Testing Federation
- Set up multiple local instances for testing.
- Test discovery, subscription, and update flows.
- Validate cross-server gem pulls and pushes.
- Edge cases: conflicting scopes/gems, network failures.

### 8. Documentation Updates
- Update API docs with federation endpoints.
- Document protocol extensions and schemas.
- Add federation setup guide.

## Deliverables
- Federated gem server capable of interacting with other instances.
- Secure validation and update sharing.
- Tests for federation scenarios.

## Risks
- Protocol complexity; mitigate by starting with a minimal viable implementation.
- Interoperability issues; test extensively with mock servers.

## Next Phase Dependencies
- Federation provides the network for key distribution and full compatibility.
