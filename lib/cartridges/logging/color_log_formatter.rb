# frozen_string_literal: true

module Cartridges
  module Logging
    # ColorLogFormatter is the console formatter: "<name> <LEVEL> - <message>",
    # wrapped in the SGR sequence that matches the severity — bold red for
    # fatal, red for error, yellow for warn, dim for debug, plain otherwise.
    #
    # Ported from cartridges/logging/color_log_formatter.py.
    class ColorLogFormatter
      RESET = "\033[0m"
      DIM = "\033[2m"
      BOLD = "\033[1m"
      RED = "\033[31m"
      YELLOW = "\033[33m"

      COLORS = {
        "FATAL" => BOLD + RED,
        "ERROR" => RED,
        "WARN" => YELLOW,
        "DEBUG" => DIM,
      }.freeze

      def call(severity, _time, progname, message)
        "#{plain(severity, progname, message)}\n".then do |line|
          COLORS[severity].then do |color|
            if color
              color + line.chomp + RESET + "\n"
            else
              line
            end
          end
        end
      end

      private

        def plain(severity, progname, message)
          [progname || "cartridges", severity, "-", message].join(" ")
        end
    end
  end
end
