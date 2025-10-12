# Authentication UI for Gem Owners

This gem server now includes a web-based authentication system for gem owners to log in and manage their gems.

## Features

- **Login/Register**: Username and password authentication using OmniAuth Identity
- **Dashboard**: View all gems you own with their status (active/yanked)
- **Session Management**: Secure cookie-based sessions
- **Password Security**: Passwords are hashed using bcrypt

## Getting Started

### 1. Run the Migration

The authentication system requires additional database columns. Run the migration:

```bash
bundle exec rake db:migrate
```

This adds `email` and `password_digest` columns to the `owners` table.

### 2. Create a User Account

You can create a test user using the provided script:

```bash
bundle exec ruby bin/create_test_user
```

This creates a user with:
- Email: `test@example.com`
- Password: `password123`

### 3. Start the Server

```bash
bundle exec hanami server
```

### 4. Access the UI

Navigate to:
- **Login**: http://localhost:2300/auth/login
- **Register**: http://localhost:2300/auth/register
- **Dashboard**: http://localhost:2300/auth/dashboard (after login)

## Routes

The following authentication routes are available:

- `GET /auth/login` - Login page
- `GET /auth/register` - Registration page
- `POST /auth/identity/callback` - OmniAuth callback (handles login)
- `POST /auth/identity/register` - OmniAuth registration
- `GET /auth/dashboard` - User dashboard (requires authentication)
- `GET /auth/logout` - Logout

## Dashboard Features

When logged in, the dashboard shows:

1. **Statistics**:
   - Total gems owned
   - Active gems count
   - Yanked gems count

2. **Gem List**: All your gems with:
   - Gem name (with scope path if applicable)
   - Version number
   - Status (Active/Yanked)
   - Creation date

## Manual User Creation

You can also create users directly via the database console:

```ruby
require_relative "config/database"
require "bcrypt"
require "securerandom"

db = Gem::Server::Database.db

db[:owners].insert(
  name: "your-username",
  email: "your-email@example.com",
  password_digest: BCrypt::Password.create("your-password"),
  api_key: SecureRandom.hex(32),
  created_at: Time.now,
  updated_at: Time.now
)
```

## Security Notes

- Passwords are hashed using bcrypt (cost factor 12)
- Sessions expire after 30 days of inactivity
- Session cookies use `SameSite: Lax` for CSRF protection
- Set a strong `SESSION_SECRET` environment variable in production

## Environment Variables

- `SESSION_SECRET` - Secret key for session encryption (required in production)

Example:
```bash
export SESSION_SECRET=$(openssl rand -hex 64)
```

## Architecture

The authentication system uses:

- **OmniAuth** - Authentication framework
- **OmniAuth Identity** - Username/password authentication strategy
- **BCrypt** - Password hashing
- **Rack::Session::Cookie** - Session management
- **Sequel** - Database ORM (Identity model uses Sequel adapter)

The `Identity` model extends `Sequel::Model` and uses the `owners` table, allowing gem owners to authenticate with email/password in addition to API keys.

