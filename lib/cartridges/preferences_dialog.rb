# frozen_string_literal: true

require "adwaita"
require_relative "shared"

module Cartridges
  # PreferencesDialog is the app's settings: general behaviour, which import
  # sources are enabled, and the SteamGridDB API key.
  #
  # Ported from cartridges/preferences.py and data/gtk/preferences.blp. The
  # per-source custom-location rows upstream shows under an expander are not
  # carried over in this round — every source still works from its built-in
  # candidate paths (see lib/cartridges/importer/location.rb); only the
  # location override UI is left out.
  class PreferencesDialog < Adwaita::PreferencesDialog
    SOURCES = {
      "steam" => "Steam",
      "lutris" => "Lutris",
      "heroic" => "Heroic",
      "bottles" => "Bottles",
      "flatpak" => "Flatpak",
      "desktop" => "Desktop Entries",
      "itch" => "itch",
      "legendary" => "Legendary",
      "retroarch" => "RetroArch",
    }.freeze

    class << self
      attr_accessor :open_instance
    end

    def initialize
      super()
      self.class.open_instance = self
      signal_connect("closed") { self.class.open_instance = nil }
      self.title = "Preferences"
    end

    def self.open? = !open_instance.nil?

    def build
      tap do |dialog|
        dialog.add(general_page)
        dialog.add(sources_page)
        dialog.add(sgdb_page)

        general_page.tap do |page|
          page.add(general_group)
          general_group.tap do |group|
            group.add(bind_switch_row(exit_after_launch_row, "exit-after-launch"))
            group.add(bind_switch_row(cover_launches_game_row, "cover-launches-game"))
            group.add(bind_switch_row(high_quality_images_row, "high-quality-images"))
            group.add(bind_switch_row(remove_missing_row, "remove-missing"))
            group.add(bind_switch_row(auto_import_row, "auto-import"))
          end
        end

        sources_page.tap do |page|
          page.add(sources_group)
          SOURCES.each { |key, label| sources_group.add(bind_switch_row(source_row(label), key)) }
        end

        sgdb_page.tap do |page|
          page.add(sgdb_group)
          sgdb_group.tap do |group|
            group.add(bind_switch_row(sgdb_enabled_row, "sgdb"))
            group.add(bind_entry_row(sgdb_key_row, "sgdb-key"))
            group.add(bind_switch_row(sgdb_prefer_row, "sgdb-prefer"))
            group.add(bind_switch_row(sgdb_animated_row, "sgdb-animated"))
          end
        end
      end
    end

    private

      def bind_switch_row(row, key)
        row.active = Shared.schema.get_boolean(key)
        row.signal_connect("notify::active") { Shared.schema.set_boolean(key, row.active?) }
        row
      end

      def bind_entry_row(row, key)
        row.text = Shared.schema.get_string(key)
        row.signal_connect("notify::text") { Shared.schema.set_string(key, row.text) }
        row
      end

      # Memoized widget methods

      def general_page
        @general_page ||= Adwaita::PreferencesPage.new.tap do |page|
          page.title = "General"
          page.icon_name = "preferences-system-symbolic"
        end
      end

      def general_group = @general_group ||= Adwaita::PreferencesGroup.new.tap { |g| g.title = "Behaviour" }

      def exit_after_launch_row
        @exit_after_launch_row ||= Adwaita::SwitchRow.new.tap do |row|
          row.title = "Exit After Launching a Game"
        end
      end

      def cover_launches_game_row
        @cover_launches_game_row ||= Adwaita::SwitchRow.new.tap do |row|
          row.title = "Cover Launches Game"
          row.subtitle = "The play button opens the game's details instead"
        end
      end

      def high_quality_images_row
        @high_quality_images_row ||= Adwaita::SwitchRow.new.tap do |row|
          row.title = "High Quality Images"
          row.subtitle = "Covers take up more disk space"
        end
      end

      def remove_missing_row
        @remove_missing_row ||= Adwaita::SwitchRow.new.tap do |row|
          row.title = "Remove Uninstalled Games"
          row.subtitle = "On import, games no longer found in a source are removed"
        end
      end

      def auto_import_row
        @auto_import_row ||= Adwaita::SwitchRow.new.tap do |row|
          row.title = "Import on Startup"
        end
      end

      def sources_page
        @sources_page ||= Adwaita::PreferencesPage.new.tap do |page|
          page.title = "Sources"
          page.icon_name = "folder-symbolic"
        end
      end

      def sources_group
        @sources_group ||= Adwaita::PreferencesGroup.new.tap do |group|
          group.title = "Import Sources"
          group.description = "Choose which installed launchers to import games from"
        end
      end

      def source_row(label) = Adwaita::SwitchRow.new.tap { |row| row.title = label }

      def sgdb_page
        @sgdb_page ||= Adwaita::PreferencesPage.new.tap do |page|
          page.title = "SteamGridDB"
          page.icon_name = "image-x-generic-symbolic"
        end
      end

      def sgdb_group = @sgdb_group ||= Adwaita::PreferencesGroup.new.tap { |g| g.title = "SteamGridDB" }

      def sgdb_enabled_row
        @sgdb_enabled_row ||= Adwaita::SwitchRow.new.tap { |row| row.title = "Download Covers From SteamGridDB" }
      end

      def sgdb_key_row
        @sgdb_key_row ||= Adwaita::EntryRow.new.tap { |row| row.title = "API Key" }
      end

      def sgdb_prefer_row
        @sgdb_prefer_row ||= Adwaita::SwitchRow.new.tap { |row| row.title = "Prefer SteamGridDB Over Official Covers" }
      end

      def sgdb_animated_row
        @sgdb_animated_row ||= Adwaita::SwitchRow.new.tap { |row| row.title = "Download Animated Covers" }
      end
  end
end
