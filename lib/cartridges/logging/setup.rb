# frozen_string_literal: true

require "logger"
require "etc"
require "open3"
require_relative "../shared"
require_relative "color_log_formatter"
require_relative "session_file_handler"

module Cartridges
  # Logging sets up the app's two log destinations — a colored console log at
  # the level the profile (or LOGLEVEL) asks for, and an uncompressed
  # per-session file at debug level — and writes the system information the
  # About dialog's debug report is built from.
  #
  # Ported from cartridges/logging/setup.py.
  module Logging
    FILE_FORMAT = "%M:%S"

    LEVELS = {
      "DEBUG" => ::Logger::DEBUG,
      "INFO" => ::Logger::INFO,
      "WARNING" => ::Logger::WARN,
      "WARN" => ::Logger::WARN,
      "ERROR" => ::Logger::ERROR,
      "CRITICAL" => ::Logger::FATAL,
      "FATAL" => ::Logger::FATAL,
      "NOTSET" => ::Logger::DEBUG,
    }.freeze

    # Logger is the facade the rest of the app logs through: one call fans out
    # to the console handler and the session file handler, each at its own
    # level, the way upstream's two logging handlers do.
    class Multiplexer
      LEVEL_METHODS = %i[debug info warn error fatal].freeze

      def initialize(targets) = @targets = targets

      LEVEL_METHODS.each do |level|
        define_method(level) { |message| @targets.each { |target| target.public_send(level, message) } }
      end

      def close = @targets.each { |target| target.close }
    end

    class << self
      def logger = @logger ||= Multiplexer.new([console_logger, file_logger])

      # Builds the handlers. Calling it again replaces them, which is what
      # makes the setup idempotent across a re-exec.
      def setup
        @logger = nil
        @console_logger = nil
        @file_logger = nil
        @file_handler = nil
        logger
      end

      def log_filename
        Shared::CACHE_DIR / "cartridges" / "logs" / "cartridges.log"
      end

      def app_log_level
        LEVELS.fetch(ENV.fetch("LOGLEVEL", profile_app_log_level).upcase, ::Logger::INFO)
      end

      def lib_log_level
        LEVELS.fetch(ENV.fetch("LIBLOGLEVEL", profile_lib_log_level).upcase, ::Logger::WARN)
      end

      def development? = Shared::PROFILE == "development"
      def profile_app_log_level = development? ? "DEBUG" : "INFO"
      def profile_lib_log_level = development? ? "INFO" : "WARNING"

      # The session log file, and the list of log files the About dialog's
      # debug information is made of.
      def file_handler
        @file_handler ||= SessionFileHandler.new(log_filename, backup_count: 2).tap do |handler|
          Shared.log_files.replace(handler.logfiles)
        end
      end

      def console_logger
        @console_logger ||= ::Logger.new($stderr).tap do |log|
          log.progname = "cartridges"
          log.level = app_log_level
          log.formatter = ColorLogFormatter.new
        end
      end

      def file_logger
        @file_logger ||= ::Logger.new(file_handler).tap do |log|
          log.level = ::Logger::DEBUG
          log.formatter = proc do |severity, time, _progname, message|
            "#{time.strftime(FILE_FORMAT)} - #{severity}: #{message}\n"
          end
        end
      end

      # The system debug information upstream writes at every start-up.
      def log_system_info
        logger.debug("Starting #{Shared::APP_ID} v#{Shared::VERSION} (#{Shared::PROFILE})")
        logger.debug("Ruby version: #{RUBY_DESCRIPTION}")
        if Shared.flatpak?
          logger.debug("Flatpak version: #{flatpak_version}")
        end
        logger.debug("Platform: #{RUBY_PLATFORM}")
        uname_lines.each { |line| logger.debug("\t#{line}") }
        logger.debug("─" * 37)
      end

      def flatpak_version
        Open3.capture2("flatpak-spawn", "--host", "flatpak", "--version").first.rstrip
      rescue Errno::ENOENT
        "unavailable"
      end

      def uname_lines
        Etc.uname.map { |key, value| "#{key.to_s.capitalize}: #{value}" }
      rescue NotImplementedError
        []
      end
    end
  end
end
