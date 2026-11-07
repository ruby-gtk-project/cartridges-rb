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
    # LutrisSourceIterable queries Lutris's pga.db for every installed,
    # named game that has a config path, skipping Steam and Flatpak games
    # unless the matching preference turns their import on, and attaches
    # the game's cover art when Lutris has downloaded one.
    #
    # Ported from the LutrisSourceIterable class in
    # cartridges/importer/lutris_source.py.
    class LutrisSourceIterable < SourceIterable
      QUERY = <<~SQL
        SELECT
          games.id,
          games.name,
          games.slug,
          games.runner,
          categories.name = '.hidden' as hidden
        FROM
          games
        LEFT JOIN
          games_categories ON games_categories.game_id = games.id
        LEFT JOIN
          categories ON games_categories.category_id = categories.id
        WHERE
          games.name IS NOT NULL
          AND games.slug IS NOT NULL
          AND games.configPath IS NOT NULL
          AND games.installed
          AND (games.runner IS NOT 'steam' OR ?1)
          AND (games.runner IS NOT 'flatpak' OR ?2)
        ;
      SQL

      def each
        db_path = Sqlite.copy_db(source.locations[:data]["pga.db"])

        begin
          SQLite3::Database.new(db_path.to_s) do |connection|
            connection.execute(QUERY, [import_steam, import_flatpak]) do |row|
              yield build(row)
            end
          end
        ensure
          FileUtils.remove_entry(db_path.dirname)
        end
      end

      private

        def import_steam = Shared.schema.get_boolean("lutris-import-steam") ? 1 : 0
        def import_flatpak = Shared.schema.get_boolean("lutris-import-flatpak") ? 1 : 0

        def build(row)
          game_id, name, slug, runner, hidden = row

          values = {
            "added" => Shared.import_time,
            "hidden" => hidden == 1,
            "name" => name,
            "source" => "#{source.source_id}_#{runner}",
            "game_id" => format(source.game_id_format, runner: runner, game_id: game_id),
            "executable" => source.make_executable(game_id: game_id),
          }

          [GameModel.new(values), cover_data(slug)]
        end

        def cover_data(slug)
          coverart_dir = source.locations[:data].root / "coverart"
          image_path = coverart_dir / "#{slug}.jpg"

          if coverart_dir.directory? && image_path.file?
            { "local_image_path" => image_path }
          else
            {}
          end
        end
    end

    # LutrisSource is the generic Lutris importer: it reads games from
    # Lutris's own database and starts them back through Lutris's
    # `lutris:rungameid/` URL scheme, which Lutris handles regardless of
    # which runner actually owns the game.
    #
    # Ported from the LutrisSource class in
    # cartridges/importer/lutris_source.py.
    class LutrisSource < URLExecutableSource
      self.source_id = "lutris"
      self.source_name = "Lutris"
      self.iterable_class = LutrisSourceIterable
      self.url_format = "lutris:rungameid/%{game_id}"
      self.available_on = %w[linux]

      def game_id_format = "#{source_id}_%{runner}_%{game_id}"

      def initialize
        super
        @locations = {
          data: Location.new(
            schema_key: "lutris-location",
            candidates: [
              Shared::FLATPAK_DIR / "net.lutris.Lutris" / "data" / "lutris",
              Shared::DATA_DIR / "lutris",
              Shared::HOST_DATA_DIR / "lutris",
            ],
            paths: {
              "pga.db" => LocationSubPath.file("pga.db"),
            },
            invalid_subtitle: Location::DATA_INVALID_SUBTITLE,
          ),
        }
      end
    end
  end
end
