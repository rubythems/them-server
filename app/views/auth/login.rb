# frozen_string_literal: true

module Them
  module Server
    module Views
      module Auth
        class Login < Them::Server::View
          expose :error

          def page_title
            "Login - Them Server"
          end
        end
      end
    end
  end
end
