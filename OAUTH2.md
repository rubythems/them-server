# OAuth2 Integration

This gem server now supports OAuth2 authentication alongside traditional API keys, providing enterprise-grade authentication with token introspection, scopes, and integration with external identity providers.

## Features

- **Multiple Authentication Schemes**: OAuth2 Bearer tokens, RubyGems API keys, HTTP Basic, and custom headers
- **OAuth2 Token Introspection** (RFC 7662): Validate tokens against authorization servers
- **Provider Support**: GitHub, GitLab, and custom OAuth2 providers
- **Backwards Compatible**: Existing API key authentication continues to work
- **Security**: WWW-Authenticate headers, proper error responses, timeout protection

## Configuration

Configure OAuth2 via environment variables:

```bash
# Required
export OAUTH2_PROVIDER_URL="https://github.com"
export OAUTH2_CLIENT_ID="your-client-id"
export OAUTH2_CLIENT_SECRET="your-client-secret"

# Optional - for token introspection (recommended)
export OAUTH2_INTROSPECTION_URL="https://github.com/oauth/token/introspect"

# Optional - custom endpoints (auto-detected for GitHub/GitLab)
export OAUTH2_TOKEN_URL="/oauth/token"
export OAUTH2_AUTHORIZE_URL="/oauth/authorize"
```

### Example: GitHub OAuth2 App

1. Create a GitHub OAuth App at https://github.com/settings/developers
2. Set Authorization callback URL to `http://localhost:9292/oauth/callback` (for development)
3. Copy the Client ID and generate a Client Secret
4. Configure environment variables:

```bash
export OAUTH2_PROVIDER_URL="https://github.com"
export OAUTH2_CLIENT_ID="Iv1.abc123..."
export OAUTH2_CLIENT_SECRET="your-secret-here"
```

### Example: GitLab OAuth2 Application

1. Create a GitLab application at https://gitlab.com/-/profile/applications
2. Set Redirect URI and select scopes (api, read_user)
3. Configure:

```bash
export OAUTH2_PROVIDER_URL="https://gitlab.com"
export OAUTH2_CLIENT_ID="your-application-id"
export OAUTH2_CLIENT_SECRET="your-secret"
```

## Usage

### Using OAuth2 Bearer Tokens

Push a gem using an OAuth2 access token:

```bash
# Get an OAuth2 access token from your provider
export GEM_HOST_API_KEY="your-oauth2-access-token"

gem push my-gem-1.0.0.gem --host http://localhost:9292
```

Or use curl with Bearer authentication:

```bash
curl -X POST http://localhost:9292/api/v1/gems \
  -H "Authorization: Bearer your-oauth2-access-token" \
  -F "gem=@my-gem-1.0.0.gem"
```

### Using Traditional API Keys (Backwards Compatible)

All existing authentication methods continue to work:

```bash
# RubyGems API key header
curl -X POST http://localhost:9292/api/v1/gems \
  -H "X-Rubygems-Api-Key: your-api-key" \
  -F "gem=@my-gem-1.0.0.gem"

# HTTP Basic authentication
curl -X POST http://localhost:9292/api/v1/gems \
  -u "your-api-key:" \
  -F "gem=@my-gem-1.0.0.gem"

# Custom API key header
curl -X POST http://localhost:9292/api/v1/gems \
  -H "X-Api-Key: your-api-key" \
  -F "gem=@my-gem-1.0.0.gem"
```

## Architecture

The OAuth2 integration consists of three main components:

### 1. OAuth2Config (`lib/gem/server/oauth2_config.rb`)

Manages OAuth2 client configuration and token validation:

- Creates and caches OAuth2::Client instances
- Validates tokens via introspection (RFC 7662)
- Falls back to provider-specific token info endpoints
- Auto-detects endpoints for GitHub and GitLab

### 2. Authenticator (`lib/gem/server/authenticator.rb`)

Unified authentication handler that tries multiple schemes:

- OAuth2 Bearer tokens (validated against provider)
- RubyGems API keys
- HTTP Basic authentication
- Custom header-based authentication

Returns structured authentication results with user info, scopes, and token metadata.

### 3. Integration with Gem Actions

The gem push and yank actions use the authenticator:

- `app/actions/gems/create.rb` - Gem publishing with OAuth2 support
- `app/actions/gems/yank.rb` - Gem yanking with OAuth2 support

## API Endpoints

### Admin: OAuth2 Status

Check OAuth2 configuration and connectivity:

```bash
GET /admin/oauth2/status
```

Response:

```json
{
  "enabled": true,
  "provider_url": "https://github.com",
  "client_id": "Iv1.abc123...",
  "has_client_secret": true,
  "introspection_enabled": false,
  "introspection_url": null,
  "client_configured": true
}
```

## Security Considerations

### Token Validation

- OAuth2 tokens are validated on every request via introspection or token info endpoints
- Invalid or expired tokens receive 401 Unauthorized responses
- Network timeouts prevent denial-of-service via slow token validation (10s timeout)

### WWW-Authenticate Headers

When OAuth2 is enabled, 401 responses include proper WWW-Authenticate headers:

```
WWW-Authenticate: Bearer realm="them-server"
```

This allows OAuth2-aware clients to automatically request new tokens.

### Secrets Management

Never commit `OAUTH2_CLIENT_SECRET` to version control. Use:

- Environment variables (12-factor app methodology)
- Secret management systems (AWS Secrets Manager, HashiCorp Vault)
- Encrypted deployment configurations

### Scopes

OAuth2 tokens include scopes that can be used for fine-grained authorization:

```ruby
auth_result = Gem::Server::Authenticator.authenticate(env)
if auth_result[:authenticated]
  scopes = auth_result[:scopes]
  if scopes.include?("write:packages")
    # Allow gem push
  end
end
```

## Testing

Test OAuth2 integration with VCR for deterministic HTTP recording:

```ruby
RSpec.describe "OAuth2 authentication" do
  it "validates tokens via introspection", :vcr do
    ENV['OAUTH2_PROVIDER_URL'] = 'https://oauth.example.com'
    ENV['OAUTH2_CLIENT_ID'] = 'test-client'
    ENV['OAUTH2_CLIENT_SECRET'] = 'test-secret'

    result = Gem::Server::Authenticator.authenticate({
      'HTTP_AUTHORIZATION' => 'Bearer valid-token'
    })

    expect(result[:authenticated]).to be true
    expect(result[:scheme]).to eq(:oauth2)
  end
end
```

## Troubleshooting

### OAuth2 Not Working

Check the admin status endpoint:

```bash
curl http://localhost:9292/admin/oauth2/status | jq
```

Verify configuration:

- `enabled` should be `true`
- `client_configured` should be `true`
- Check for any `error` field

### Token Validation Fails

- Ensure the OAuth2 provider is reachable
- Check that `OAUTH2_PROVIDER_URL` is correct
- Verify the token hasn't expired
- Look for errors in server logs

### Introspection Not Supported

Some providers don't support RFC 7662 introspection. The system automatically falls back to token info endpoints:

- GitHub: `/user`
- GitLab: `/api/v4/user`
- Custom: `/oauth/token/info`

## RFC References

- [RFC 6749](https://datatracker.ietf.org/doc/html/rfc6749) - OAuth 2.0 Authorization Framework
- [RFC 6750](https://datatracker.ietf.org/doc/html/rfc6750) - OAuth 2.0 Bearer Token Usage
- [RFC 7662](https://datatracker.ietf.org/doc/html/rfc7662) - OAuth 2.0 Token Introspection
- [RFC 7617](https://datatracker.ietf.org/doc/html/rfc7617) - HTTP Basic Authentication
- [RFC 8414](https://datatracker.ietf.org/doc/html/rfc8414) - OAuth 2.0 Authorization Server Metadata

## Migration from API Keys

OAuth2 is opt-in and backwards compatible:

1. Keep existing API key authentication working
2. Add OAuth2 configuration for new users
3. Gradually migrate users to OAuth2 tokens
4. Eventually deprecate API keys if desired

The gem server will accept both authentication methods simultaneously.
