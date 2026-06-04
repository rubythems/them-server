# frozen_string_literal: true

module Them
  module Server
    class Settings < Hanami::Settings
      setting :database_url,
        default: "sqlite://config/db/them_server.sqlite",
        constructor: Types::String
    end
  end
end
