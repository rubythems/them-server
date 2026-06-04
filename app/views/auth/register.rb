# frozen_string_literal: true

module Them
  module Server
    module Views
      module Auth
        class Register < Them::Server::View
          expose :error

          def page_title
            "Register - Them Server"
          end
        end
      end
    end
  end
end

