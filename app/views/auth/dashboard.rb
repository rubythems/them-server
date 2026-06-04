# frozen_string_literal: true

module Them
  module Server
    module Views
      module Auth
        class Dashboard < Them::Server::View
          expose :owner
          expose :gems
          expose :user_name
          expose :user_email

          def page_title
            "Dashboard - Them Server"
          end

          def gem_count
            gems.size
          end
        end
      end
    end
  end
end
