# frozen_string_literal: true

require "json"
require "rack"
require_relative "../../../../config/database"

module Gem
  module Server
    module Actions
      module Admin
        module KnownServers
          class Toggle < Gem::Server::Action
            def handle(request, response)
              db = Database.db
              payload = parse_payload(request)
              base_url = payload["base_url"].to_s.strip
              subscribed = payload.key?("subscribed") ? truthy?(payload["subscribed"]) : nil

              if base_url.empty? || subscribed.nil?
                response.status = 400
                response.body = "Missing required fields"
                return
              end

              row = db[:known_servers].where(base_url: base_url).first
              unless row
                response.status = 404
                response.body = "Unknown server"
                return
              end

              db[:known_servers].where(id: row[:id]).update(subscribed: subscribed, updated_at: Time.now)

              # If HTML form submitted, redirect back to UI; else return JSON
              if html_request?(request)
                response.status = 303
                response.redirect_to "/admin"
              else
                response.format = :json
                response.status = 200
                response.body = JSON.generate({base_url: base_url, subscribed: subscribed})
              end
            rescue JSON::ParserError
              response.status = 400
              response.body = "Invalid JSON"
            end

            private

            def parse_payload(request)
              content_type = (request.env["CONTENT_TYPE"] || "").downcase
              if content_type.start_with?("application/json")
                body = request.body
                begin
                  body.rewind
                rescue StandardError
                end
                JSON.parse(body.read.to_s)
              else
                # Support standard HTML form submissions
                rack_req = ::Rack::Request.new(request.env)
                rack_req.params
              end
            rescue StandardError
              {}
            end

            def truthy?(val)
              return val if val == true || val == false
              %w[1 true on yes].include?(val.to_s.downcase)
            end

            def html_request?(request)
              accept = (request.env["HTTP_ACCEPT"] || "").downcase
              ref = (request.env["HTTP_REFERER"] || "").downcase
              accept.include?("text/html") || ref.include?("/admin")
            end
          end
        end
      end
    end
  end
end
