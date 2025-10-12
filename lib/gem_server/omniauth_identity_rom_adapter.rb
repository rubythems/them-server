# frozen_string_literal: true

require "bcrypt"

module Gem
  module Server
    # ROM adapter for OmniAuth::Identity
    # This provides a reusable adapter that makes ROM entities compatible with OmniAuth::Identity
    #
    # Usage:
    #   class Identity
    #     include Gem::Server::OmniAuthIdentityRomAdapter
    #
    #     # Configure the ROM container and relation
    #     self.rom_container = -> { Gem::Server::Database.rom }
    #     self.rom_relation_name = :owners
    #     self.auth_key_field = :email  # optional, defaults to :email
    #     self.password_field = :password_digest  # optional, defaults to :password_digest
    #   end
    module OmniAuthIdentityRomAdapter
      def self.included(base)
        base.extend(ClassMethods)
        base.include(BCrypt)
      end

      module ClassMethods
        attr_accessor :rom_container, :rom_relation_name, :auth_key_field, :password_field

        # OmniAuth::Identity required method
        def auth_key
          @auth_key_field || :email
        end

        # OmniAuth::Identity required method
        # Authenticates a user based on the provided conditions
        #
        # @param conditions [Hash] Authentication credentials (e.g., {email: "user@example.com", password: "secret"})
        # @return [Object, nil] An instance of the identity model or nil if authentication fails
        def authenticate(conditions)
          email = conditions[auth_key] || conditions[auth_key.to_s]
          password = conditions[:password] || conditions["password"]
          return nil unless email && password

          # Get the ROM relation
          container = rom_container.respond_to?(:call) ? rom_container.call : rom_container
          relation = container.relations[rom_relation_name || :owners]

          # Query for the user
          password_field_name = @password_field || :password_digest
          user_data = relation.where(auth_key => email).one
          return nil unless user_data
          return nil unless user_data[password_field_name]

          # Verify password using BCrypt
          begin
            if BCrypt::Password.new(user_data[password_field_name]) == password
              new(user_data)
            else
              nil
            end
          rescue BCrypt::Errors::InvalidHash
            nil
          end
        end

        # Optional: Method to locate a user by auth key
        # @param key [String] The value of the auth key to search for
        # @return [Object, nil] An instance of the identity model or nil if not found
        def locate(key)
          container = rom_container.respond_to?(:call) ? rom_container.call : rom_container
          relation = container.relations[rom_relation_name || :owners]
          user_data = relation.where(auth_key => key).one
          user_data ? new(user_data) : nil
        end
      end

      # Instance methods for OmniAuth::Identity compatibility
      attr_reader :uid, :email, :name, :info

      def initialize(user_data)
        @user_data = user_data
        @uid = user_data[:id]
        @email = user_data[:email]
        @name = user_data[:name] || user_data[:email]
        @info = {
          "email" => @email,
          "name" => @name
        }
      end

      # Access to the underlying user data hash
      def [](key)
        @user_data[key]
      end

      # OmniAuth info hash
      def to_hash
        @info
      end
    end
  end
end

