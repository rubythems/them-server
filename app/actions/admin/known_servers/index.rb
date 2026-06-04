# frozen_string_literal: true

require "json"
require_relative "../../../../config/database"

module Them
  module Server
    module Actions
      module Admin
        module KnownServers
          class Index < Them::Server::Action
            def handle(_request, response)
              db = Database.db
              rows = db[:known_servers].all
              response.format = :json
              response.status = 200
              response.body = JSON.generate(rows.map { |r|
                {
                  base_url: r[:base_url],
                  subscribed: r[:subscribed],
                  public_key_b64: r[:public_key_b64],
                  last_announced_at: r[:last_announced_at],
                  last_seen_at: r[:last_seen_at],
                  created_at: r[:created_at],
                  updated_at: r[:updated_at]
                }
              })
            end
          end
        end
      end
    end
  end
end
