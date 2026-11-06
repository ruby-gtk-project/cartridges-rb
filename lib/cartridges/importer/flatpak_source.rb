# frozen_string_literal: true

require "adwaita"
require "pathname"
require_relative "source"
require_relative "location"
require_relative "../game_model"
require_relative "../shared"

module Cartridges
  module Importer
    # FlatpakSourceIterable reads the exported desktop entries of the system
    # and user Flatpak installations, keeps the ones in the Game category, and
    # looks their icons up in the exported icon themes.
    #
    # Ported from the FlatpakSourceIterable class in
    # cartridges/importer/flatpak_source.py.
    class FlatpakSourceIterable < SourceIterable
      # Cartridges itself, which is never imported.
      SELF_IDS = %w[
        hu.kramo.Cartridges
        hu.kramo.Cartridges.Devel
        page.kramo.Cartridges
        page.kramo.Cartridges.Devel
      ].freeze

      # The other launchers, which have importers of their own and are only
      # imported when the user asks for launchers too.
      LAUNCHER_IDS = %w[
        com.valvesoftware.Steam
        net.lutris.Lutris
        com.heroicgameslauncher.hgl
        com.usebottles.Bottles
        io.itch.itch
        org.libretro.RetroArch
      ].freeze

      ICON_SIZE = 512

      def each
        if data_locations.empty?
          nil
        else
          desktop_entries.each do |entry|
            entry_values(entry).then do |values|
              if values
                yield [GameModel.new(values[:game]), values[:data]]
              end
            end
          end
        end
      end

      private

        def blacklist
          if Shared.schema.get_boolean("flatpak-import-launchers")
            SELF_IDS
          else
            SELF_IDS + LAUNCHER_IDS
          end
        end

        def data_locations
          [source.locations[:user_data], source.locations[:system_data]].compact
        end

        def icon_theme
          @icon_theme ||= Gtk::IconTheme.new.tap do |theme|
            data_locations.each do |location|
              location["icons"].then { |icons| icons && theme.add_search_path(icons.to_s) }
            end
          end
        end

        def desktop_entries
          data_locations.filter_map { |location| location["applications"] }
                        .flat_map { |dir| dir.children }
                        .select { |entry| entry.extname == ".desktop" }
        end

        def entry_values(entry)
          keyfile(entry).then do |keyfile|
            if keyfile && game?(keyfile) && own_id?(keyfile, entry)
              flatpak_id(keyfile).then do |flatpak_id|
                { game: game_values(keyfile, flatpak_id), data: icon_data(keyfile) }
              end
            end
          end
        end

        def keyfile(entry)
          GLib::KeyFile.new.tap { |file| file.load_from_file(entry.to_s, 0) }
        rescue GLib::Error
          nil
        end

        def game?(keyfile)
          keyfile.get_string_list("Desktop Entry", "Categories").include?("Game")
        rescue GLib::Error
          false
        end

        # A game's entry is the one whose X-Flatpak matches its own filename;
        # anything else is an extra launcher the app exported.
        def own_id?(keyfile, entry)
          flatpak_id(keyfile).then do |flatpak_id|
            flatpak_id && !blacklist.include?(flatpak_id) && flatpak_id == entry.basename(".desktop").to_s
          end
        end

        def flatpak_id(keyfile)
          keyfile.get_string("Desktop Entry", "X-Flatpak")
        rescue GLib::Error
          nil
        end

        def game_values(keyfile, flatpak_id)
          {
            "source" => source.source_id,
            "added" => Shared.import_time,
            "name" => keyfile.get_string("Desktop Entry", "Name"),
            "game_id" => format(source.game_id_format, game_id: flatpak_id),
            "executable" => source.make_executable(flatpak_id: flatpak_id),
          }
        end

        def icon_data(keyfile)
          icon_path(keyfile).then do |path|
            if path
              { "local_icon_path" => Pathname.new(path) }
            else
              {}
            end
          end
        end

        def icon_path(keyfile)
          icon_theme.lookup_icon(
            keyfile.get_string("Desktop Entry", "Icon"),
            nil,
            ICON_SIZE,
            1,
            Shared.win&.window&.direction || :none,
            0,
          ).file&.path
        rescue GLib::Error
          nil
        end
    end

    # FlatpakSource is the Flatpak importer, which starts games with
    # `flatpak run`.
    #
    # Ported from the FlatpakSource class in
    # cartridges/importer/flatpak_source.py. Both of its locations are
    # optional: a machine may have only a system or only a user installation.
    class FlatpakSource < ExecutableFormatSource
      self.source_id = "flatpak"
      self.source_name = "Flatpak"
      self.iterable_class = FlatpakSourceIterable
      self.executable_format = "flatpak run %{flatpak_id}"
      self.available_on = %w[linux]

      EXPORTED_PATHS = {
        "applications" => "exports/share/applications",
        "icons" => "exports/share/icons",
      }.freeze

      def initialize
        super
        @locations = {
          system_data: exported_location("flatpak-system-location", ["/var/lib/flatpak/"]),
          user_data: exported_location("flatpak-user-location", [Shared::DATA_DIR / "flatpak"]),
        }
      end

      private

        def exported_location(schema_key, candidates)
          Location.new(
            schema_key: schema_key,
            candidates: candidates,
            paths: EXPORTED_PATHS.transform_values { |segment| LocationSubPath.directory(segment) },
            invalid_subtitle: Location::DATA_INVALID_SUBTITLE,
            optional: true,
          )
        end
    end
  end
end
