# frozen_string_literal: true

require "fileutils"
require "sqlite3"
require_relative "source"
require_relative "location"
require_relative "../game_model"
require_relative "../shared"
require_relative "../sqlite"

module Cartridges
  module Importer
    # ItchSourceIterable queries itch's butler.db for every cave (installed
    # copy of a game) and the game it belongs to, and attaches whichever
    # cover URL itch has — the still cover when there is one, the regular
    # cover otherwise.
    #
    # Ported from the ItchSourceIterable class in
    # cartridges/importer/itch_source.py.
    class ItchSourceIterable < SourceIterable
      QUERY = <<~SQL
        SELECT
          games.id,
          games.title,
          games.cover_url,
          games.still_cover_url,
          caves.id
        FROM
          'caves'
        INNER JOIN
          'games'
        ON
          caves.game_id = games.id
        ;
      SQL

      def each
        db_path = Sqlite.copy_db(source.locations[:config]["butler.db"])

        begin
          SQLite3::Database.new(db_path.to_s) do |connection|
            connection.execute(QUERY) { |row| yield build(row) }
          end
        ensure
          FileUtils.remove_entry(db_path.dirname)
        end
      end

      private

        def build(row)
          game_id, title, cover_url, still_cover_url, cave_id = row

          values = {
            "added" => Shared.import_time,
            "source" => source.source_id,
            "name" => title,
            "game_id" => format(source.game_id_format, game_id: game_id),
            "executable" => source.make_executable(cave_id: cave_id),
          }

          [GameModel.new(values), { "online_cover_url" => still_cover_url || cover_url }]
        end
    end

    # ItchSource is the itch (itch.io desktop app) importer, which starts
    # games back through itch's own `itch://caves/<id>/launch` URL scheme.
    #
    # Ported from the ItchSource class in cartridges/importer/itch_source.py.
    class ItchSource < URLExecutableSource
      self.source_id = "itch"
      self.source_name = "itch"
      self.iterable_class = ItchSourceIterable
      self.url_format = "itch://caves/%{cave_id}/launch"
      self.available_on = %w[linux win32 darwin]

      def initialize
        super
        @locations = {
          config: Location.new(
            schema_key: "itch-location",
            candidates: [
              Shared::FLATPAK_DIR / "io.itch.itch" / "config" / "itch",
              Shared::CONFIG_DIR / "itch",
              Shared::HOST_CONFIG_DIR / "itch",
              Shared::APPDATA_DIR / "itch",
              Shared::APP_SUPPORT_DIR / "itch",
            ],
            paths: {
              "butler.db" => LocationSubPath.file("db/butler.db"),
            },
            invalid_subtitle: Location::CONFIG_INVALID_SUBTITLE,
          ),
        }
      end
    end
  end
end
