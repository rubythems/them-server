# OmniAuth::Identity ROM Adapter

A reusable adapter that makes ROM (Ruby Object Mapper) entities compatible with OmniAuth::Identity, similar to the Sequel adapter that ships with the omniauth-identity gem.

## Features

- **Drop-in ROM support** for OmniAuth::Identity authentication
- **BCrypt password hashing** built-in
- **Flexible configuration** - customize relation names and field names
- **Simple API** - just include the module and configure

## Installation

Copy `omniauth_identity_rom_adapter.rb` to your project's `lib` directory.

## Usage

### Basic Setup

```ruby
class Identity
  include Gem::Server::OmniAuthIdentityRomAdapter

  # Configure the ROM container and relation
  self.rom_container = -> { MyApp::Database.rom }
  self.rom_relation_name = :users  # or :owners, :accounts, etc.
  self.auth_key_field = :email     # optional, defaults to :email
  self.password_field = :password_digest  # optional, defaults to :password_digest
end
```

### Configuration Options

| Option | Default | Description |
|--------|---------|-------------|
| `rom_container` | required | A ROM container instance or a lambda that returns one |
| `rom_relation_name` | `:owners` | The name of the ROM relation to use |
| `auth_key_field` | `:email` | The field used for authentication (username/email) |
| `password_field` | `:password_digest` | The field containing the BCrypt password hash |

### ROM Relation Setup

Your ROM relation should have the following schema:

```ruby
module MyApp
  module Relations
    class Users < ROM::Relation[:sql]
      schema(:users, infer: true)
      
      # Required fields:
      # - id (primary key)
      # - email (or your configured auth_key_field)
      # - password_digest (or your configured password_field)
      # - name (optional, for display purposes)
    end
  end
end
```

### Database Schema

Your database table should have these columns:

```ruby
create_table :users do
  primary_key :id
  String :email, null: false, unique: true
  String :password_digest, null: false
  String :name
  DateTime :created_at
  DateTime :updated_at
end
```

### OmniAuth Configuration

Configure OmniAuth to use your Identity model:

```ruby
use OmniAuth::Builder do
  provider :identity,
    fields: [:email],
    model: MyApp::Models::Identity
end
```

## API Reference

### Class Methods

#### `.auth_key`
Returns the field name used for authentication (e.g., `:email`).

#### `.authenticate(conditions)`
Authenticates a user with the provided credentials.

**Parameters:**
- `conditions` (Hash): Authentication credentials
  - `:email` or auth_key - The user's identifier
  - `:password` - The user's password

**Returns:**
- Identity instance if authentication succeeds
- `nil` if authentication fails

**Example:**
```ruby
identity = Identity.authenticate(
  email: "user@example.com",
  password: "secret123"
)
```

#### `.locate(key)`
Finds a user by their auth key value.

**Parameters:**
- `key` (String): The value to search for (e.g., email address)

**Returns:**
- Identity instance if found
- `nil` if not found

**Example:**
```ruby
identity = Identity.locate("user@example.com")
```

### Instance Methods

#### `#uid`
Returns the user's unique identifier (id).

#### `#email`
Returns the user's email address.

#### `#name`
Returns the user's display name (falls back to email if not set).

#### `#info`
Returns a hash containing user information for OmniAuth:
```ruby
{
  "email" => "user@example.com",
  "name" => "User Name"
}
```

#### `#[](key)`
Access the underlying user data hash.

**Example:**
```ruby
identity[:created_at]  # => 2025-10-12 10:30:00
```

#### `#to_hash`
Returns the info hash (alias for `#info`).

## How It Works

The adapter:

1. **Queries the ROM relation** using the configured auth key
2. **Retrieves the user data** as a hash from ROM
3. **Verifies the password** using BCrypt
4. **Returns an Identity instance** that wraps the user data
5. **Provides OmniAuth-compatible methods** (uid, email, name, info)

## Password Hashing

The adapter uses BCrypt for secure password hashing. Your application should:

1. Hash passwords before storing them:
```ruby
require 'bcrypt'

hashed_password = BCrypt::Password.create("user_password")
# Store hashed_password in the password_digest field
```

2. The adapter automatically verifies passwords during authentication using BCrypt

## Comparison to Sequel Adapter

This ROM adapter provides equivalent functionality to the Sequel adapter that ships with omniauth-identity:

| Feature | Sequel Adapter | ROM Adapter |
|---------|---------------|-------------|
| OmniAuth compatibility | ✅ | ✅ |
| BCrypt password hashing | ✅ | ✅ |
| Configurable field names | ✅ | ✅ |
| Authentication | ✅ | ✅ |
| User lookup | ✅ | ✅ |
| Database agnostic | ✅ | ✅ |

## Requirements

- Ruby 2.7+
- ROM (ruby-object-mapper) 5.0+
- BCrypt 3.1+
- OmniAuth Identity 3.0+

## License

This adapter is provided as-is for use in your projects.

## Contributing

Contributions are welcome! This adapter can be extracted into a separate gem if there's interest from the community.

## Example Project

See the gem-server project for a complete working example of this adapter in action.

