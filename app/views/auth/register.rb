# frozen_string_literal: true

module Gem
  module Server
    module Views
      module Auth
        class Register < Gem::Server::View
          expose :error

          def page_title
            "Register - Gem Server"
          end
        end
      end
    end
  end
end

