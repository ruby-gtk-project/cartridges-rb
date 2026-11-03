# frozen_string_literal: true

require "json"
require_relative "source"
require_relative "location"
require_relative "../game_model"
require_relative "../shared"
require_relative "../logging/setup"

module Cartridges
  module Importer
    # LegendarySourceIterable reads Legendary's installed.json and produces
    # one game per entry that is not DLC, pulling the developer and the tall
    # box art out of the per-game metadata file when there is one.
    #
    # Ported from the LegendarySourceIterable class in
    # cartridges/importer/legendary_source.py.
    class LegendarySourceIterable < SourceIterable
      # The key image type Epic uses for a portrait cover.
      COVER_IMAGE_TYPE = "DieselGameBoxTall"

      def each
        library.then do |entries|
          entries.each_value do |entry|
            game_from_library_entry(entry).then do |result|
              if result
                yield result
              end
            end
          end
        end
      end

      private

        def library
          source.locations[:config]["installed.json"].then do |file|
            JSON.parse(File.read(file))
          rescue JSON::ParserError, SystemCallError
            Logging.logger.warn("Couldn't open Legendary file: #{file}")
            {}
          end
        end

        def game_from_library_entry(entry)
          if entry["is_dlc"]
            nil
          else
            build(entry)
          end
        rescue KeyError => e
          Logging.logger.warn("Invalid Legendary game skipped: #{e.message}")
          nil
        end

        def build(entry)
          entry.fetch("app_name").then do |app_name|
            values(entry, app_name).then do |values|
              metadata(app_name).then do |extra|
                [GameModel.new(values.merge(extra[:values])), extra[:data]]
              end
            end
          end
        end

        def values(entry, app_name)
          {
            "added" => Shared.import_time,
            "source" => source.source_id,
            "name" => entry.fetch("title"),
            "game_id" => format(source.game_id_format, game_id: app_name),
            "executable" => source.make_executable(app_name: app_name),
          }
        end

        # The metadata file is optional; a missing or broken one just means no
        # developer and no cover.
        def metadata(app_name)
          JSON.parse(File.read(source.locations[:config]["metadata"] / "#{app_name}.json"))
              .fetch("metadata")
              .then { |meta| { values: { "developer" => meta.fetch("developer") }, data: cover(meta) } }
        rescue JSON::ParserError, SystemCallError, KeyError
          { values: {}, data: {} }
        end

        def cover(meta)
          Array(meta["keyImages"]).find { |image| image["type"] == COVER_IMAGE_TYPE }
                                  .then { |image| image ? { "online_cover_url" => image["url"] } : {} }
        end
    end

    # LegendarySource is the Legendary (Epic Games CLI) importer, which starts
    # games through the legendary command.
    #
    # Ported from the LegendarySource class in
    # cartridges/importer/legendary_source.py.
    class LegendarySource < ExecutableFormatSource
      self.source_id = "legendary"
      self.source_name = "Legendary"
      self.executable_format = "legendary launch %{app_name}"
      self.available_on = %w[linux]
      self.iterable_class = LegendarySourceIterable

      def initialize
        super
        @locations = {
          config: Location.new(
            schema_key: "legendary-location",
            candidates: [
              Shared::CONFIG_DIR / "legendary",
              Shared::HOST_CONFIG_DIR / "legendary",
            ],
            paths: {
              "installed.json" => LocationSubPath.file("installed.json"),
              "metadata" => LocationSubPath.directory("metadata"),
            },
            invalid_subtitle: Location::CONFIG_INVALID_SUBTITLE,
          ),
        }
      end
    end
  end
end
