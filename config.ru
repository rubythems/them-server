# frozen_string_literal: true

require "securerandom"
require "rack/session/cookie"
require "hanami/boot"
require_relative "lib/them_server/auth_app"

# Shared session for Hanami and Rodauth
use Rack::Session::Cookie,
    secret: ENV.fetch("SESSION_SECRET", SecureRandom.hex(64)),
    key: "them_server.session",
    same_site: :lax,
    max_age: 86400 * 30

map "/auth" do
  run Gem::Server::AuthenticationApp.app
end

map "/" do
  run Hanami.app
end
