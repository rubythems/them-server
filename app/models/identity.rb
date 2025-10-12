# frozen_string_literal: true

module Gem
  module Server
    module Models
      # Identity model for OmniAuth Identity authentication
      # Uses the ROM adapter for database access
      class Identity
        include Gem::Server::OmniAuthIdentityRomAdapter

        # Configure the ROM adapter
        self.rom_container = -> { Gem::Server::Database.rom }
        self.rom_relation_name = :owners
        self.auth_key_field = :email
        self.password_field = :password_digest
      end
    end
  end
end
