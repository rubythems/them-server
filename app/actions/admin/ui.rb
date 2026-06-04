# frozen_string_literal: true

require "erb"
require "json"
require_relative "../../../config/database"

module Them
  module Server
    module Actions
      module Admin
        class Ui < Them::Server::Action
          TEMPLATE_PATH = File.expand_path("../../templates/admin/ui.html.erb", __dir__)

          def handle(_request, response)
            db = Database.db
            known = db[:known_servers].order(:base_url).all
            metrics = {
              known_servers_total: db[:known_servers].count,
              known_servers_subscribed: db[:known_servers].where(subscribed: true).count,
              federated_gems_total: (db.table_exists?(:federated_gems) ? db[:federated_gems].count : 0),
            }

            html = render_template(known, metrics)
            response.headers["content-type"] = "text/html; charset=utf-8"
            response.status = 200
            response.body = html
          end

          private

          def render_template(known, metrics)
            tpl = File.read(TEMPLATE_PATH)
            ERB.new(tpl).result(binding)
          end
        end
      end
    end
  end
end
