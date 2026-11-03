# frozen_string_literal: true

require "adwaita"
require "pathname"
require_relative "settings"

module Cartridges
  # AppState is the state the application is in, which decides how aggressively
  # the window reacts to games appearing and disappearing.
  #
  # Ported from the AppState IntEnum in cartridges/shared.py.in.
  module AppState
    DEFAULT = 1
    LOAD_FROM_DISK = 2
    IMPORT = 3
    REMOVE_ALL_GAMES = 4
    UNDO_REMOVE_ALL_GAMES = 5
  end

  # Shared holds the globals the rest of the app reads: the app id, the two
  # Gio::Settings, every XDG / host / flatpak directory the importers look in,
  # and the handful of mutable slots upstream keeps at module level (the
  # window, the importer, the store, the import timestamp, the log files).
  #
  # Ported from cartridges/shared.py.in. The meson-substituted constants are
  # resolved here rather than at build time, since this port has no meson.
  module Shared
    APP_ID = Settings::APP_ID
    VERSION = "2.13.1"
    PREFIX = "/page/kramo/Cartridges"
    PROFILE = "release"

    # Upstream's meson option offers webp and jpeg; GdkPixbuf's TIFF saver
    # takes a numeric libtiff compression code instead, so the equivalent
    # lossy choice is 7 (JPEG-in-TIFF) and the high-quality one is 8 (Deflate).
    TIFF_COMPRESSION = "7"
    HIGH_QUALITY_TIFF_COMPRESSION = "8"

    # The version of the game_id.json spec this port reads and writes.
    SPEC_VERSION = 1.5

    HOME = Pathname.new(Dir.home)

    DATA_DIR = Pathname.new(GLib.user_data_dir)
    HOST_DATA_DIR = Pathname.new(ENV.fetch("HOST_XDG_DATA_HOME", (HOME / ".local" / "share").to_s))

    CONFIG_DIR = Pathname.new(GLib.user_config_dir)
    HOST_CONFIG_DIR = Pathname.new(ENV.fetch("HOST_XDG_CONFIG_HOME", (HOME / ".config").to_s))

    CACHE_DIR = Pathname.new(GLib.user_cache_dir)
    HOST_CACHE_DIR = Pathname.new(ENV.fetch("HOST_XDG_CACHE_HOME", (HOME / ".cache").to_s))

    FLATPAK_DIR = HOME / ".var" / "app"

    GAMES_DIR = DATA_DIR / "cartridges" / "games"
    COVERS_DIR = DATA_DIR / "cartridges" / "covers"

    APPDATA_DIR = Pathname.new(ENV.fetch("appdata", 'C:\Users\Default\AppData\Roaming'))
    LOCAL_APPDATA_DIR = Pathname.new(ENV.fetch("csidl_local_appdata", 'C:\Users\Default\AppData\Local'))
    PROGRAMFILES32_DIR = Pathname.new(ENV.fetch("programfiles(x86)", 'C:\Program Files (x86)'))

    APP_SUPPORT_DIR = HOME / "Library" / "Application Support"

    # RUBY_PLATFORM spellings mapped to the sys.platform names upstream's
    # sources list in their available_on sets.
    PLATFORM_PATTERNS = {
      "linux" => /linux/,
      "win32" => /mingw|mswin|cygwin/,
      "darwin" => /darwin/,
    }.freeze

    class << self
      # The two schemas. Deferred rather than resolved at load time so that
      # requiring the library never needs a compiled schema present.
      def schema = Settings.schema
      def state_schema = Settings.state_schema

      # The cover size, in pixels, at the largest scale factor of any attached
      # monitor. Falls back to the unscaled size when there is no display at
      # all, which is the case in the search provider and under a bare Xvfb.
      def image_size = @image_size ||= [200 * scale_factor, 300 * scale_factor]

      def scale_factor
        @scale_factor ||= Gdk::Display.default.then do |display|
          if display
            monitor_scale_factors(display.monitors).max || 1
          else
            1
          end
        end
      rescue NoMethodError, GLib::Error
        1
      end

      # Gdk::Display#monitors is a Gio::ListModel, which these bindings expose
      # through n_items / get_item rather than as an Enumerable.
      def monitor_scale_factors(monitors)
        (0...monitors.n_items).map { |index| monitors.get_item(index).scale_factor }
      end

      # The platform string the importer sources compare against, spelled the
      # way Python's sys.platform spells it so the sources' available_on sets
      # port over unchanged.
      def platform
        @platform ||= PLATFORM_PATTERNS.find { |_name, pattern| RUBY_PLATFORM.match?(pattern) }
                                       &.first || RUBY_PLATFORM
      end

      def flatpak? = ENV["FLATPAK_ID"] == APP_ID

      # Mutable module-level slots, exactly the ones upstream keeps in
      # shared.py: the window, the running importer, the import timestamp, the
      # store and the session's log files.
      attr_accessor :win, :importer, :import_time, :store

      def log_files = @log_files ||= []
    end
  end
end
