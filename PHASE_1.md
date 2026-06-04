# Phase 1: Basic Them Server with Scopes and Permissions

## Overview
This phase focuses on building the core gem server functionality, including support for scoped namespaces and a permissions system. The server will handle gem pushes, pulls, and management within scopes, with authentication and authorization for owners.

## Objectives
- Implement a basic Ruby web server capable of serving gems.
- Support scoped gem namespaces with up to 3 levels of nesting.
- Provide API endpoints for gem operations (push, pull, list, yank).
- Implement permissions: gem owners and scope owners with hierarchical control.
- Ensure basic security with authentication (e.g., API keys or signatures).

## Steps

### 1. Set Up Project Structure and Dependencies
- Use Hanami as the web framework.
- Add necessary gems: hanami, rack, json, sqlite3 for storage, bcrypt for hashing, etc.
- Initialize database schema for scopes, gems, owners, permissions.
- Set up basic server configuration and routing.

### 2. Implement Scope Parsing and Storage
- Create models for Scope (hierarchical, up to 3 levels).
- Implement path parsing logic to extract scope-path and gem name from URLs (e.g., /{org}/{sub}/{gem}).
- Store scopes in database with parent-child relationships.
- Add validation for URL-safe scope names.

### 3. Basic Gem Storage and Retrieval
- Create Gem model with metadata (name, version, scope, file data).
- Implement file storage (local filesystem or cloud storage like S3).
- Add endpoints for pulling gems: `GET /{scope-path}/{gem}` returns gem file.
- Add endpoint for listing gems in scope: `GET /{scope-path}` returns JSON list of gems.

### 4. Implement Gem Push Functionality
- Add push endpoint: `POST /{scope-path}` accepts multipart upload with gem file and metadata.
- Validate gem name (no slashes), version, and scope existence.
- Store gem in database and filesystem.
- Basic validation (e.g., gem format).

### 5. Permissions System
- Create Owner model with public keys or API keys.
- Implement authentication middleware (e.g., signature verification or API key check).
- Add GemOwner and ScopeOwner associations.
- Implement authorization checks for push/yank operations.
- Add endpoints for managing owners: `POST /{scope-path}/{gem}/owners`, `DELETE /{scope-path}/{gem}/owners/{owner}` (scope owner only).

### 6. Yank and Version Management
- Add yank endpoint: `DELETE /{scope-path}/{gem}/versions/{version}` (gem owner only).
- Implement version history and soft deletes for yanked gems.
- Ensure yanked gems are not served in pulls.

### 7. Testing and Validation
- Write unit tests for models, parsing, and endpoints.
- Integration tests for push/pull cycles.
- Test permissions with mock owners.
- Validate against RubyGems client compatibility (basic).

### 8. Documentation and API Specs
- Document all API endpoints with examples.
- Create OpenAPI/Swagger spec for the API.
- Update README with setup and usage instructions.

## Deliverables
- Functional gem server with scoped namespaces.
- Permissions enforced on all operations.
- Basic tests passing.
- API documentation.

## Risks
- Scope parsing complexity; mitigate with thorough testing.
- Performance with file storage; start simple, optimize later.

## Next Phase Dependencies
- This phase provides the foundation for federation and key management.
