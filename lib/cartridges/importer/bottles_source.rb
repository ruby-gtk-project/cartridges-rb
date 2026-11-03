# frozen_string_literal: true

require "pathname"
require "yaml"
require_relative "source"
require_relative "location"
require_relative "../game_model"
require_relative "../shared"

module Cartridges
  module Importer
    # BottlesSourceIterable reads Bottles' library.yml and produces one game
    # per entry, with the grid image from the bottle it belongs to.
    #
    # Ported from the BottlesSourceIterable class in
    # cartridges/importer/bottles_source.py.
    class BottlesSourceIterable < SourceIterable
      def each
        library.each_value do |entry|
          yield [build(entry), cover_data(entry)]
        end
      end

      private

        def library
          YAML.safe_load(File.read(source.locations[:data]["library.yml"], encoding: "UTF-8")) || {}
        end

        def build(entry)
          GameModel.new(
            "source" => source.source_id,
            "added" => Shared.import_time,
            "name" => entry["name"],
            "game_id" => format(source.game_id_format, game_id: entry["id"]),
            "executable" => source.make_executable(
              bottle_name: entry.dig("bottle", "name"),
              game_name: entry["name"],
            ),
          )
        end

        def cover_data(entry)
          entry["thumbnail"].then do |thumbnail|
            if thumbnail.to_s.empty?
              {}
            else
              {
                "local_image_path" => bottles_location / entry.dig("bottle", "path") / "grids" /
                  thumbnail.to_s.split(":")[1].to_s,
              }
            end
          end
        end

        # Bottles may keep its bottles somewhere the user picked, recorded in
        # data.yml. That path is unreadable when both apps are Flatpaks, since
        # it came from Bottles' own file-chooser portal.
        def bottles_location
          custom_bottles_path || (source.locations[:data].root / "bottles")
        end

        def custom_bottles_path
          YAML.safe_load(File.read(source.locations[:data]["data.yml"], encoding: "UTF-8"))
              .then { |data| data && data["custom_bottles_path"] && Pathname.new(data["custom_bottles_path"]) }
        rescue SystemCallError, Psych::SyntaxError
          nil
        end
    end

    # BottlesSource is the Bottles importer, which starts games through the
    # bottles:// URL scheme.
    #
    # Ported from the BottlesSource class in
    # cartridges/importer/bottles_source.py.
    class BottlesSource < URLExecutableSource
      self.source_id = "bottles"
      self.source_name = "Bottles"
      self.iterable_class = BottlesSourceIterable
      self.url_format = 'bottles:run/"%{bottle_name}"/"%{game_name}"'
      self.available_on = %w[linux]

      def initialize
        super
        @locations = {
          data: Location.new(
            schema_key: "bottles-location",
            candidates: [
              Shared::FLATPAK_DIR / "com.usebottles.bottles" / "data" / "bottles",
              Shared::DATA_DIR / "bottles",
              Shared::HOST_DATA_DIR / "bottles",
            ],
            paths: {
              "library.yml" => LocationSubPath.file("library.yml"),
              "data.yml" => LocationSubPath.file("data.yml"),
            },
            invalid_subtitle: Location::DATA_INVALID_SUBTITLE,
          ),
        }
      end
    end
  end
end
