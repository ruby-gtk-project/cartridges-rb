# frozen_string_literal: true

require "digest"
require "json"
require "pathname"
require "shellwords"
require_relative "source"
require_relative "location"
require_relative "../game_model"
require_relative "../shared"
require_relative "../friendly_error"
require_relative "../logging/setup"

module Cartridges
  module Importer
    # RetroarchSourceIterable reads every RetroArch playlist (.lpl) under the
    # configured playlist directory and produces one game per entry, using
    # the entry's own core when it has one and the playlist's default core
    # otherwise. A playlist with no usable core for one of its entries is
    # skipped and reported as a FriendlyError once the whole import is done.
    #
    # Ported from the RetroarchSourceIterable class in
    # cartridges/importer/retroarch_source.py.
    class RetroarchSourceIterable < SourceIterable
      def each
        bad_playlists = []

        playlist_files.each do |playlist_file|
          playlist = read_playlist(playlist_file)
          next unless playlist

          playlist.fetch("items", []).each do |item|
            core_path = item["core_path"]
            core_path = playlist["default_core_path"] if core_path.nil? || core_path == "DETECT" || core_path == ""

            if core_path.nil? || core_path == "DETECT" || core_path == ""
              Logging.logger.warn("Cannot find core for: #{item["path"]}")
              bad_playlists << playlist_file.basename(".lpl").to_s
              next
            end

            yield build(item, core_path, playlist_file)
          end
        end

        unless bad_playlists.empty?
          raise FriendlyError.new(
            "No RetroArch Core Selected",
            "The following playlists have no default core:\n\n{}\n\nGames with no core selected were not imported",
            subtitle_args: [bad_playlists.join("\n")],
          )
        end
      end

      private

        def config_value(key, config_data)
          match = config_data.match(/#{key}\s*=\s*"(.*)"\n/i)
          raise KeyError, "Key not found in RetroArch config: #{key}" unless match

          match[1].start_with?(":") ? match[1].sub(":", source.locations[:config].root.to_s) : match[1]
        end

        def config_data = @config_data ||= File.read(source.locations[:config]["retroarch.cfg"], encoding: "UTF-8")

        def playlist_folder = Pathname.new(config_value("playlist_directory", config_data)).expand_path
        def thumbnail_folder = Pathname.new(config_value("thumbnails_directory", config_data)).expand_path

        def playlist_files = Pathname.glob(playlist_folder / "*.lpl")

        def read_playlist(path)
          JSON.parse(File.read(path, encoding: "UTF-8"))
        rescue JSON::ParserError, SystemCallError
          Logging.logger.warn("Cannot read playlist file: #{path}")
          nil
        end

        def build(item, core_path, playlist_file)
          game_id = Digest::MD5.hexdigest(item["path"].to_s)

          values = {
            "source" => source.source_id,
            "added" => Shared.import_time,
            "name" => item["label"],
            "game_id" => format(source.game_id_format, game_id: game_id),
            "executable" => source.make_executable(core_path: core_path, rom_path: item["path"]),
          }

          boxart_name = "#{item["label"]}.png".gsub(%r{[&*/:`<>?\\|]}, "_")
          image_path = thumbnail_folder / playlist_file.basename(".lpl").to_s / "Named_Boxarts" / boxart_name

          [GameModel.new(values), { "local_image_path" => image_path }]
        end
    end

    # RetroarchSource is the RetroArch importer: it reads playlists from the
    # configured RetroArch install and starts games through the core/ROM
    # pair, either natively or (when RetroArch itself is a Flatpak) through
    # `flatpak run`.
    #
    # Ported from the RetroarchSource class in
    # cartridges/importer/retroarch_source.py. The commented-out Steam/UWP
    # support upstream has not shipped yet is left out here too.
    class RetroarchSource < Source
      self.source_id = "retroarch"
      self.source_name = "RetroArch"
      self.iterable_class = RetroarchSourceIterable
      self.available_on = %w[linux]

      def initialize
        super
        @locations = {
          config: Location.new(
            schema_key: "retroarch-location",
            candidates: [
              Shared::FLATPAK_DIR / "org.libretro.RetroArch" / "config" / "retroarch",
              Shared::CONFIG_DIR / "retroarch",
              Shared::HOST_CONFIG_DIR / "retroarch",
            ],
            paths: {
              "retroarch.cfg" => LocationSubPath.file("retroarch.cfg"),
            },
            invalid_subtitle: Location::CONFIG_INVALID_SUBTITLE,
          ),
        }
      end

      def make_executable(core_path:, rom_path:)
        @locations[:config].resolve
        args = [core_path, rom_path].map { |s| Shellwords.escape(s.to_s) }.join(" ")

        if @locations[:config].root.to_s.start_with?(Shared::FLATPAK_DIR.to_s)
          "flatpak run org.libretro.RetroArch -L #{args}"
        else
          "retroarch -L #{args}"
        end
      end
    end
  end
end
