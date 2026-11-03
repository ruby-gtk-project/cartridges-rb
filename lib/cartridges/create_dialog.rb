# frozen_string_literal: true

require "adwaita"

module Cartridges
  # CreateDialog is the factory every error and confirmation path in the app
  # goes through: an Adwaita::AlertDialog with a heading, a body, a "Dismiss"
  # response and optionally one extra response, presented over a window.
  #
  # Ported from cartridges/utils/create_dialog.py.
  module CreateDialog
    class << self
      def call(win, heading, body, extra_option: nil, extra_label: nil)
        Adwaita::AlertDialog.new(heading, body).tap do |dialog|
          dialog.add_response("dismiss", "Dismiss")

          if extra_option
            dialog.add_response(extra_option, extra_label.to_s)
          end

          dialog.choose(win)
        end
      end
    end
  end
end
