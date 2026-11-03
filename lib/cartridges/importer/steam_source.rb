# frozen_string_literal: true

require "pathname"
require_relative "source"
require_relative "location"
require_relative "../game_model"
require_relative "../steam"
require_relative "../shared"
require_relative "../logging/setup"

module Cartridges
  module Importer
    # SteamSourceIterable walks every steamapps directory libraryfolders.vdf
    # points at, reads the app manifests it finds there, and produces the
    # installed, not-yet-seen ones.
    #
    # Ported from the SteamSourceIterable class in
    # cartridges/importer/steam_source.py.
    class SteamSourceIterable < SourceIterable
      # Bit 4 of an app manifest's stateflags means "fully installed".
      INSTALLED_MASK = 4

      # The steamapps directories the library folders file lists.
      def manifest_dirs
        File.read(source.locations[:data]["libraryfolders.vdf"], encoding: "UTF-8").then do |contents|
          contents.scan(/"path"\s+"(.*)"\n/i).flatten.map { |path| Pathname.new(path) / "steamapps" }
        end
      end

      # Every app manifest under those directories.
      def manifests
        manifest_dirs.select(&:directory?)
                     .flat_map { |dir| Pathname.glob(dir / "appmanifest_*.acf") }
                     .select(&:file?)
                     .uniq
      end

      def each
        Set.new.then do |appid_cache|
          manifests.each do |manifest|
            manifest_data(manifest).then do |local_data|
              if local_data && admissible?(manifest, local_data, appid_cache)
                appid_cache.add(local_data["appid"])
                yield build(local_data)
              end
            end
          end
        end
      end

      private

        def manifest_data(manifest)
          SteamFileHelper.new.manifest_data(manifest)
        rescue SystemCallError, SteamInvalidManifestError => e
          Logging.logger.debug("Couldn't load appmanifest #{manifest}: #{e.message}")
          nil
        end

        def admissible?(manifest, local_data, appid_cache)
          if (local_data["stateflags"].to_i & INSTALLED_MASK).zero?
            Logging.logger.debug("Skipped #{manifest}: not installed")
            false
          elsif appid_cache.include?(local_data["appid"])
            Logging.logger.debug("Skipped #{manifest}: appid already seen during import")
            false
          else
            true
          end
        end

        def build(local_data)
          local_data["appid"].then do |appid|
            [
              GameModel.new(
                "added" => Shared.import_time,
                "name" => local_data["name"],
                "source" => source.source_id,
                "game_id" => format(source.game_id_format, game_id: appid),
                "executable" => source.make_executable(game_id: appid),
              ),
              {
                "local_image_path" => source.locations[:data]["librarycache"] / appid / "library_600x900.jpg",
                "steam_appid" => appid,
              },
            ]
          end
        end
    end

    # SteamSource is the Steam library importer: it reads the local app
    # manifests and starts games through the steam:// URL scheme.
    #
    # Ported from the SteamSource class in cartridges/importer/steam_source.py.
    class SteamSource < URLExecutableSource
      self.source_id = "steam"
      self.source_name = "Steam"
      self.available_on = %w[linux win32 darwin]
      self.iterable_class = SteamSourceIterable
      self.url_format = "steam://rungameid/%{game_id}"

      def initialize
        super
        @locations = {
          data: Location.new(
            schema_key: "steam-location",
            candidates: [
              Shared::HOME / ".steam" / "steam",
              Shared::DATA_DIR / "Steam",
              Shared::FLATPAK_DIR / "com.valvesoftware.Steam" / "data" / "Steam",
              Shared::PROGRAMFILES32_DIR / "Steam",
              Shared::APP_SUPPORT_DIR / "Steam",
            ],
            paths: {
              "libraryfolders.vdf" => LocationSubPath.file("steamapps/libraryfolders.vdf"),
              "librarycache" => LocationSubPath.directory("appcache/librarycache"),
            },
            invalid_subtitle: Location::DATA_INVALID_SUBTITLE,
          ),
        }
      end
    end
  end
end
