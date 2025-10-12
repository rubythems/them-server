# frozen_string_literal: true

module Gem
  module Server
    class Routes < Hanami::Routes
      # Authentication endpoints
      get "/auth/login", to: "auth.login"
      get "/auth/register", to: "auth.register"
      get "/auth/dashboard", to: "auth.dashboard"
      get "/auth/logout", to: "auth.logout"
      post "/auth/identity/callback", to: "auth.callback"
      get "/auth/identity/callback", to: "auth.callback"

      # Federation endpoints
      post "/federation/announce", to: "federation.announce"
      post "/federation/subscribe", to: "federation.subscribe"
      post "/federation/push", to: "federation.push"
      get "/federation/validate/scope/*path", to: "federation.validate_scope"
      get "/federation/validate/gem/*path", to: "federation.validate_gem"

      # Admin endpoints
      get "/admin", to: "admin.ui"
      get "/admin/known_servers", to: "admin.known_servers.index"
      post "/admin/known_servers/toggle", to: "admin.known_servers.toggle"
      get "/admin/federation/metrics", to: "admin.federation.metrics"
      get "/admin/oauth2/status", to: "admin.oauth2.status"

      # Add your routes here. See https://guides.hanamirb.org/routing/overview/ for details.
      get "/*path", to: "gems.show"
      post "/api/v1/gems", to: "gems.create"
      post "/*path", to: "gems.create"
      delete "/*path/versions/:version", to: "gems.yank"
    end
  end
end
