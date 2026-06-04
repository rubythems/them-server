# frozen_string_literal: true

require "json"
require_relative "../../../../config/database"

module Them
  module Server
    module Actions
      module Admin
        module Federation
          class Metrics < Them::Server::Action
            def handle(_request, response)
              db = Database.db
              known = db[:known_servers]
              fedg = db[:federated_gems]

              metrics = {
                known_servers_total: known.count,
                known_servers_subscribed: known.where(subscribed: true).count,
                federated_gems_total: fedg.count,
                last_seen_latest: known.exclude(last_seen_at: nil).order(Sequel.desc(:last_seen_at)).get(:last_seen_at),
                last_announced_latest: known.exclude(last_announced_at: nil).order(Sequel.desc(:last_announced_at)).get(:last_announced_at),
              }

              response.format = :json
              response.status = 200
              response.body = JSON.generate(metrics)
            end
          end
        end
      end
    end
  end
end

