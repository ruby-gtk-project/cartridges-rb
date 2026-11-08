# frozen_string_literal: true

require "gtk4"
require "adwaita"
require "json"
require "uri"
require_relative "shared"
require_relative "game_model"
require_relative "window"
require_relative "details_dialog"
require_relative "preferences_dialog"
require_relative "shortcuts_dialog"
require_relative "run_executable"
require_relative "store"
require_relative "store/managers/file_manager"
require_relative "store/managers/display_manager"
require_relative "store/managers/cover_manager"
require_relative "store/managers/steam_api_manager"
require_relative "store/managers/sgdb_manager"
require_relative "importer/importer"
require_relative "importer/steam_source"
require_relative "importer/flatpak_source"
require_relative "importer/bottles_source"
require_relative "importer/legendary_source"
require_relative "importer/desktop_source"
require_relative "importer/retroarch_source"
require_relative "importer/heroic_source"
require_relative "importer/lutris_source"
require_relative "importer/itch_source"

module Cartridges
  # Application is the app entry point: it builds the window, loads the
  # games already on disk, wires up every app-scoped action (launch, hide,
  # edit, add, import, remove, the per-site search links, preferences,
  # shortcuts, about, quit), and runs the import sources this round ported.
  #
  # Ported from cartridges/main.py. House style (see .claude/skills/ruby-gtk):
  # every widget is a memoized method, all configuration lives in its `tap`,
  # assembly happens only in `build`, and the launcher is one expression.
  class Application
    ACTIONS = {
      "quit" => ["<Control>q"],
      "about" => [],
      "preferences" => ["<Control>comma"],
      "launch_game" => [],
      "hide_game" => [],
      "edit_game" => [],
      "add_game" => ["<Control>n"],
      "import" => ["<Control>i"],
      "remove_game_details_view" => ["Delete"],
      "remove_game" => [],
      "igdb_search" => [],
      "sgdb_search" => [],
      "protondb_search" => [],
      "pcgw_search" => [],
      "lutris_search" => [],
      "hltb_search" => [],
      "shortcuts" => ["<Control>question"],
    }.freeze

    WINDOW_ACTIONS = {
      "show_sidebar" => ["F9"],
      "show_hidden" => ["<Control>h"],
      "go_to_parent" => ["<alt>Up"],
      "go_home" => ["<alt>Home"],
      "toggle_search" => ["<Control>f"],
      "undo" => ["<Control>z"],
      "open_menu" => ["F10"],
      "close" => ["<Control>w"],
    }.freeze

    def initialize
      Shared.store = Store.new
    end

    def build
      app.tap do
        app.signal_connect("activate") { activate }
      end
    end

    def run = build.run([])

    def app = @app ||= Gtk::Application.new(Shared::APP_ID, :default_flags)

    def main_window = @main_window ||= Window.new(app)

    private

      def activate
        return if Shared.win

        load_css

        Shared.win = main_window
        main_window.build

        bind_window_geometry
        load_games_from_disk
        main_window.create_source_rows

        add_runtime_managers
        setup_app_actions
        set_accelerators

        main_window.window.present

        schedule_auto_import if Shared.schema.get_boolean("auto-import")
      end

      # Loads lib/cartridges/style.css as an application-priority provider,
      # the purple accent overrides and #details_view rules upstream ships
      # as data/gtk/style.css + style-dark.css (one stylesheet here, since
      # GTK 4 honours the `prefers-color-scheme` media query directly).
      # 600 is GTK_STYLE_PROVIDER_PRIORITY_APPLICATION; the Ruby bindings
      # don't expose it as a constant, so it's passed as the raw integer.
      CSS_PROVIDER_PRIORITY_APPLICATION = 600

      def load_css
        Gtk::StyleContext.add_provider_for_display(Gdk::Display.default, css_provider, CSS_PROVIDER_PRIORITY_APPLICATION)
      end

      def css_provider
        @css_provider ||= Gtk::CssProvider.new.tap { |provider| provider.load_from_path(File.join(__dir__, "style.css")) }
      end

      def bind_window_geometry
        win = main_window.window
        Shared.state_schema.bind("width", win, "default-width", :default)
        Shared.state_schema.bind("height", win, "default-height", :default)
        Shared.state_schema.bind("is-maximized", win, "maximized", :default)
      end

      def load_games_from_disk
        Shared.store.add_manager(Store::FileManager.new, in_pipeline: false)
        Shared.store.add_manager(Store::DisplayManager.new)
        Shared.app_state = AppState::LOAD_FROM_DISK

        if Shared::GAMES_DIR.directory?
          Shared::GAMES_DIR.each_child do |path|
            next unless path.extname == ".json"

            read_game_file(path)
          end
        end

        Shared.app_state = AppState::DEFAULT
      end

      def read_game_file(path)
        data = JSON.parse(File.read(path))
        Shared.store.add_game(GameModel.new(data), { "skip_save" => true })
      rescue JSON::ParserError, SystemCallError
        nil
      end

      def schedule_auto_import
        GLib::Idle.add do
          on_import_action
          false
        end
      end

      def add_runtime_managers
        Shared.store.add_manager(Store::CoverManager.new)
        Shared.store.add_manager(Store::SteamAPIManager.new)
        Shared.store.add_manager(Store::SgdbManager.new)
        Shared.store.toggle_manager_in_pipelines(Store::FileManager, true)
      end

      def setup_app_actions
        ACTIONS.each_key do |name|
          Gio::SimpleAction.new(name, nil).tap do |action|
            action.signal_connect("activate") { |*_args| send("on_#{name}_action") }
            app.add_action(action)
          end
        end
      end

      def set_accelerators
        ACTIONS.each { |name, accels| app.set_accels_for_action("app.#{name}", accels) unless accels.empty? }
        WINDOW_ACTIONS.each { |name, accels| app.set_accels_for_action("win.#{name}", accels) unless accels.empty? }
      end

      # --- app.* actions, ported from CartridgesApplication's on_*_action --

      def on_quit_action = app.quit

      def on_about_action
        Adwaita::AboutDialog.new.tap do |about|
          about.application_name = "Cartridges"
          about.application_icon = Shared::APP_ID
          about.version = Shared::VERSION
          about.developer_name = "kramo"
          about.copyright = "© 2022-2024 kramo"
          about.license_type = :gpl_3_0
          about.website = "https://github.com/kra-mo/cartridges"
          about.present(main_window.window)
        end
      end

      def on_preferences_action
        return if PreferencesDialog.open?

        PreferencesDialog.new.build.present(main_window.window)
      end

      def on_shortcuts_action = ShortcutsDialog.new.build.present(main_window.window)

      def on_launch_game_action
        main_window.game_tiles[main_window.active_game&.game_id]&.launch
      end

      def on_hide_game_action
        main_window.game_tiles[main_window.active_game&.game_id]&.toggle_hidden
      end

      def on_edit_game_action
        DetailsDialog.new(main_window.active_game).build.present(main_window.window) if main_window.active_game
      end

      def on_add_game_action
        return if DetailsDialog.open?

        DetailsDialog.new.build.present(main_window.window)
      end

      def on_remove_game_action
        main_window.game_tiles[main_window.active_game&.game_id]&.remove_game
      end

      def on_remove_game_details_view_action
        on_remove_game_action if main_window.navigation_view.visible_page == main_window.details_page
      end

      def on_import_action
        Shared.importer = Importer::Importer.new

        {
          "steam" => Importer::SteamSource,
          "flatpak" => Importer::FlatpakSource,
          "bottles" => Importer::BottlesSource,
          "legendary" => Importer::LegendarySource,
          "desktop" => Importer::DesktopSource,
          "retroarch" => Importer::RetroarchSource,
          "heroic" => Importer::HeroicSource,
          "lutris" => Importer::LutrisSource,
          "itch" => Importer::ItchSource,
        }.each do |key, klass|
          Shared.importer.add_source(klass.new) if Shared.schema.get_boolean(key)
        end

        Shared.importer.run
      end

      def search(uri)
        Gio::AppInfo.launch_default_for_uri("#{uri}#{URI.encode_www_form_component(main_window.active_game.name)}", nil)
      end

      def on_igdb_search_action = search("https://www.igdb.com/search?type=1&q=")
      def on_sgdb_search_action = search("https://www.steamgriddb.com/search/grids?term=")
      def on_protondb_search_action = search("https://www.protondb.com/search?q=")
      def on_pcgw_search_action = search("https://www.pcgamingwiki.com/w/index.php?search=")
      def on_lutris_search_action = search("https://lutris.net/games?q=")
      def on_hltb_search_action = search("https://howlongtobeat.com/?q=")
  end
end
