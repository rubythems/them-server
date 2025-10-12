# frozen_string_literal: true

module Gem
  module Server
    module Views
      module Auth
        class Login < Gem::Server::View
          expose :error

          def page_title
            "Login - Gem Server"
          end
        end
      end
    end
  end
end

