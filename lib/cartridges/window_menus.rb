# frozen_string_literal: true

require "gtk4"

module Cartridges
  # WindowMenus builds the Gio::Menu models the window's header bars show:
  # the main menu (sort submenu, show hidden, preferences/shortcuts/about),
  # the add-game split-button menu, and the details page's per-site search
  # menu.
  #
  # Ported from the `primary_menu`, `add_games` and `search` menu models in
  # data/gtk/window.blp.
  module WindowMenus
    class << self
      def primary_menu
        @primary_menu ||= Gio::Menu.new.tap do |menu|
          menu.append_section(nil, Gio::Menu.new.tap { |section| section.append_submenu("Sort", sort_submenu) })
          menu.append_item(Gio::MenuItem.new("Show Hidden", "win.show_hidden"))
          menu.append_section(
            nil,
            Gio::Menu.new.tap do |section|
              section.append("Preferences", "app.preferences")
              section.append("Keyboard Shortcuts", "app.shortcuts")
              section.append("About Cartridges", "app.about")
            end,
          )
        end
      end

      def sort_submenu
        @sort_submenu ||= Gio::Menu.new.tap do |menu|
          {
            "A-Z" => "a-z",
            "Z-A" => "z-a",
            "Newest" => "newest",
            "Oldest" => "oldest",
            "Last Played" => "last_played",
          }.each do |label, target|
            menu.append_item(Gio::MenuItem.new(label, "win.sort_by").tap { |item| item.set_action_and_target_value("win.sort_by", GLib::Variant.new(target)) })
          end
        end
      end

      def add_games
        @add_games ||= Gio::Menu.new.tap do |menu|
          menu.append_section(nil, Gio::Menu.new.tap { |section| section.append("Add Game", "app.add_game") })
          menu.append_section(nil, Gio::Menu.new.tap { |section| section.append("Import", "app.import") })
        end
      end

      def search
        @search ||= Gio::Menu.new.tap do |menu|
          menu.append_section(
            "Search on…",
            Gio::Menu.new.tap do |section|
              section.append("IGDB", "app.igdb_search")
              section.append("SteamGridDB", "app.sgdb_search")
              section.append("ProtonDB", "app.protondb_search")
              section.append("PCGamingWiki", "app.pcgw_search")
              section.append("Lutris", "app.lutris_search")
              section.append("HowLongToBeat", "app.hltb_search")
            end,
          )
        end
      end
    end
  end
end
