# frozen_string_literal: true

require "digest"
require "json"
require "pathname"
require "set"
require_relative "source"
require_relative "location"
require_relative "../game_model"
require_relative "../shared"
require_relative "../logging/setup"

module Cartridges
  module Importer
    # InvalidLibraryFileError is raised when a Heroic sub-source's
    # library.json cannot be read or is missing the keys this importer needs.
    #
    # Ported from InvalidLibraryFileError in cartridges/importer/heroic_source.py.
    class InvalidLibraryFileError < StandardError; end

    # InvalidInstalledFileError is raised when a Heroic store's installed.json
    # cannot be read or is missing the keys this importer needs.
    #
    # Ported from InvalidInstalledFileError in cartridges/importer/heroic_source.py.
    class InvalidInstalledFileError < StandardError; end

    # InvalidStoreFileError is raised when Heroic's store/config.json (which
    # carries the hidden app list) cannot be read.
    #
    # Ported from InvalidStoreFileError in cartridges/importer/heroic_source.py.
    class InvalidStoreFileError < StandardError; end

    # SubSourceIterable produces games from one Heroic sub-source's
    # library.json. Sideload games have no separate installed list; the
    # store-backed sub-sources (Legendary/Epic, GOG, Nile/Amazon) subclass
    # StoreSubSourceIterable to filter to installed games only.
    #
    # Ported from the SubSourceIterable class in
    # cartridges/importer/heroic_source.py.
    class SubSourceIterable
      include Enumerable

      attr_reader :source, :source_iterable

      def initialize(source, source_iterable)
        @source = source
        @source_iterable = source_iterable
      end

      def library_path = source.locations[:config].root / relative_library_path

      def each
        entries.each do |entry|
          result = process_library_entry(entry)
          yield result if result
        rescue KeyError => e
          Logging.logger.warn("Skipped invalid Heroic #{name} game #{entry["app_name"] || "UNKNOWN"}: #{e.message}")
        end
      end

      def process_library_entry(entry)
        app_name = entry.fetch("app_name")
        runner = entry.fetch("runner")

        values = {
          "source" => "#{source.source_id}_#{service}",
          "added" => Shared.import_time,
          "name" => entry.fetch("title"),
          "developer" => entry["developer"],
          "game_id" => format(source.game_id_format, service: service, game_id: app_name),
          "executable" => source.make_executable(runner: runner, app_name: app_name),
          "hidden" => source_iterable.hidden?(app_name),
        }
        game = GameModel.new(values)

        uri = "#{entry.fetch("art_square")}#{image_uri_params}"
        digest = Digest::SHA256.hexdigest(uri)
        image_path = source.locations[:config].root / "images-cache" / digest

        [game, { "local_image_path" => image_path }]
      end

      private

        def entries
          JSON.parse(File.read(library_path)).fetch(library_json_entries_key)
        rescue SystemCallError, JSON::ParserError, TypeError, KeyError => e
          raise InvalidLibraryFileError, "Invalid #{library_path.basename}: #{e.message}"
        end

        def image_uri_params = ""
        def library_json_entries_key = "library"
    end

    # StoreSubSourceIterable is a Heroic sub-source whose games can be
    # installed or not; only the installed ones are imported.
    #
    # Ported from the StoreSubSourceIterable class in
    # cartridges/importer/heroic_source.py.
    class StoreSubSourceIterable < SubSourceIterable
      def installed_path = source.locations[:config].root / relative_installed_path

      def installed?(app_name) = installed_app_names.include?(app_name)

      def process_library_entry(entry)
        app_name = entry.fetch("app_name")
        unless installed?(app_name)
          Logging.logger.warn("Skipped #{service} game #{entry["title"]} (#{app_name}): not installed")
          return nil
        end
        super
      end

      def each(&block)
        @installed_app_names = get_installed_app_names
        super(&block)
      end

      private

        def installed_app_names = @installed_app_names ||= get_installed_app_names
    end

    # SideloadIterable is the Heroic sub-source for manually added games,
    # which carries no separate installed list.
    #
    # Ported from SideloadIterable in cartridges/importer/heroic_source.py.
    class SideloadIterable < SubSourceIterable
      def name = "sideload"
      def service = "sideload"
      def relative_library_path = Pathname.new("sideload_apps") / "library.json"
      def library_json_entries_key = "games"
    end

    # LegendaryIterable is the Heroic sub-source for Epic Games Store titles
    # installed through the bundled Legendary.
    #
    # Ported from LegendaryIterable in cartridges/importer/heroic_source.py.
    class LegendaryIterable < StoreSubSourceIterable
      def name = "legendary"
      def service = "epic"
      def image_uri_params = "?h=400&resize=1&w=300"
      def relative_library_path = Pathname.new("store_cache") / "legendary_library.json"

      # Heroic >= 2.9 keeps a legendaryConfig directory alongside its own
      # config; Heroic <= 2.8 keeps Legendary's own config dir instead (the
      # Flatpak's own config for the Flatpak build, the host's for native).
      def installed_path
        config_root = source.locations[:config].root
        base =
          if (config_root / "legendaryConfig").directory?
            config_root
          elsif config_root.to_s.start_with?(Shared::FLATPAK_DIR.to_s)
            Shared::FLATPAK_DIR / "com.heroicgameslauncher.hgl" / "config"
          else
            Shared::HOST_CONFIG_DIR
          end
        base / "legendary" / "installed.json"
      end

      private

        def get_installed_app_names
          JSON.parse(File.read(installed_path)).keys
        rescue SystemCallError, JSON::ParserError, TypeError => e
          raise InvalidInstalledFileError, "Invalid #{installed_path.basename}: #{e.message}"
        end
    end

    # GogIterable is the Heroic sub-source for GOG titles.
    #
    # Ported from GogIterable in cartridges/importer/heroic_source.py.
    class GogIterable < StoreSubSourceIterable
      def name = "gog"
      def service = "gog"
      def library_json_entries_key = "games"
      def relative_library_path = Pathname.new("store_cache") / "gog_library.json"
      def relative_installed_path = Pathname.new("gog_store") / "installed.json"

      private

        def get_installed_app_names
          JSON.parse(File.read(installed_path))
              .fetch("installed")
              .filter_map { |entry| entry["appName"] }
        rescue SystemCallError, JSON::ParserError, TypeError, KeyError => e
          raise InvalidInstalledFileError, "Invalid #{installed_path.basename}: #{e.message}"
        end
    end

    # NileIterable is the Heroic sub-source for Amazon Games titles.
    #
    # Ported from NileIterable in cartridges/importer/heroic_source.py.
    class NileIterable < StoreSubSourceIterable
      def name = "nile"
      def service = "amazon"
      def relative_library_path = Pathname.new("store_cache") / "nile_library.json"
      def relative_installed_path = Pathname.new("nile_config") / "nile" / "installed.json"

      private

        def get_installed_app_names
          JSON.parse(File.read(installed_path)).filter_map { |entry| entry["id"] }
        rescue SystemCallError, JSON::ParserError, TypeError => e
          raise InvalidInstalledFileError, "Invalid #{installed_path.basename}: #{e.message}"
        end
    end

    # HeroicSourceIterable chains the four Heroic sub-sources (sideload,
    # Legendary/Epic, GOG, Nile/Amazon), skipping whichever ones the user
    # disabled or whose files are broken.
    #
    # Ported from the HeroicSourceIterable class in
    # cartridges/importer/heroic_source.py.
    class HeroicSourceIterable < SourceIterable
      SUB_SOURCE_CLASSES = [SideloadIterable, LegendaryIterable, GogIterable, NileIterable].freeze

      def hidden?(app_name) = hidden_app_names.include?(app_name)

      def each
        @hidden_app_names = get_hidden_app_names

        SUB_SOURCE_CLASSES.each do |klass|
          sub_source = klass.new(source, self)
          next unless Shared.schema.get_boolean("heroic-import-#{sub_source.service}")

          begin
            sub_source.each { |result| yield result }
          rescue InvalidLibraryFileError, InvalidInstalledFileError => e
            Logging.logger.error("Skipping bad Heroic sub-source #{sub_source.service}: #{e.message}")
          end
        end
      end

      private

        def hidden_app_names = @hidden_app_names ||= get_hidden_app_names

        def get_hidden_app_names
          store = JSON.parse(File.read(source.locations[:config]["store_config.json"]))
          store.fetch("games").fetch("hidden").filter_map { |game| game["appName"] }.to_set
        rescue KeyError
          Logging.logger.warn('No ["games"]["hidden"] key in Heroic store file')
          Set.new
        rescue SystemCallError, JSON::ParserError, TypeError => e
          Logging.logger.error("Invalid Heroic store file: #{e.message}")
          raise InvalidStoreFileError
        end
    end

    # HeroicSource is the Heroic Games Launcher importer: one source that
    # fans out into four sub-sources (sideload, Legendary/Epic, GOG,
    # Nile/Amazon), each gated by its own GSettings switch.
    #
    # Ported from the HeroicSource class in cartridges/importer/heroic_source.py.
    class HeroicSource < URLExecutableSource
      self.source_id = "heroic"
      self.source_name = "Heroic"
      self.url_format = "heroic://launch/%{runner}/%{app_name}"
      self.available_on = %w[linux win32 darwin]
      self.iterable_class = HeroicSourceIterable

      def game_id_format = "#{source_id}_%{service}_%{game_id}"

      def initialize
        super
        @locations = {
          config: Location.new(
            schema_key: "heroic-location",
            candidates: [
              Shared::CONFIG_DIR / "heroic",
              Shared::HOST_CONFIG_DIR / "heroic",
              Shared::FLATPAK_DIR / "com.heroicgameslauncher.hgl" / "config" / "heroic",
              Shared::APPDATA_DIR / "heroic",
              Shared::APP_SUPPORT_DIR / "heroic",
            ],
            paths: {
              "config.json" => LocationSubPath.file("config.json"),
              "store_config.json" => LocationSubPath.file("store/config.json"),
            },
            invalid_subtitle: Location::CONFIG_INVALID_SUBTITLE,
          ),
        }
      end
    end
  end
end
