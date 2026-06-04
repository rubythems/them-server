# frozen_string_literal: true

require "bcrypt"

module Them
  module Server
    module Repos
      class OwnerRepository
        include BCrypt

        def initialize(rom_container)
          @owners = rom_container.relations[:owners]
        end

        def by_email(email)
          @owners.where(email: email).one
        end

        def by_api_key(api_key)
          @owners.where(api_key: api_key).one
        end

        def authenticate(email:, password:)
          owner = by_email(email)
          return nil unless owner && owner[:password_digest]

          begin
            if Password.new(owner[:password_digest]) == password
              owner
            else
              nil
            end
          rescue BCrypt::Errors::InvalidHash
            nil
          end
        end

        def all
          @owners.to_a
        end
      end
    end
  end
end
