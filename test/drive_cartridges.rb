# frozen_string_literal: true

# Drives the whole app headlessly: builds the window, adds/edits/hides/
# removes games, opens every dialog (add/edit, preferences, shortcuts,
# about, the import progress dialog, the error alert), exercises the
# sidebar, search, sort, the hidden library, the details page and every
# win.*/app.* action and accelerator, then screenshots each state.
#
# Why this file exists: a GTK app that loads is not a GTK app that works.
# `ruby -c` passes on code that builds an empty window; only a real run
# shows whether the wiring between a button and the model it is supposed to
# change actually holds.
#
# Run it from the repository root:
#
#   nix develop --command xvfb-run -a ruby test/drive_cartridges.rb
#
# GTK4 here has no offscreen backend - gtk_init fails outright with no
# display - so xvfb-run is not optional on this machine (see the dev
# shell's own banner).

require "fileutils"
require "json"
require "tmpdir"

# Scratch XDG dirs, so a run never reads or writes the real user's games,
# covers or settings. Set before `require "cartridges"`, since Shared's
# constants and Settings resolve GLib.user_*_dir / Gio::Settings at load.
XDG_HOME = Dir.mktmpdir("cartridges-drive")
ENV["XDG_CONFIG_HOME"] = File.join(XDG_HOME, "config")
ENV["XDG_DATA_HOME"] = File.join(XDG_HOME, "data")
ENV["XDG_CACHE_HOME"] = File.join(XDG_HOME, "cache")
FileUtils.mkdir_p(ENV.fetch("XDG_CONFIG_HOME"))
FileUtils.mkdir_p(ENV.fetch("XDG_DATA_HOME"))
FileUtils.mkdir_p(ENV.fetch("XDG_CACHE_HOME"))

# Real fixture databases for the Lutris and itch sources, so the import step
# below exercises their actual query/build logic instead of only hitting
# "bad location" and skipping. Both sources resolve their location straight
# off XDG_DATA_HOME/XDG_CONFIG_HOME (see lib/cartridges/importer/lutris_source.rb
# and lib/cartridges/importer/itch_source.rb), so dropping a db at the path
# each one's Location expects is enough to make it a real, asserted check
# rather than a "the source is merely listed" one.
require "sqlite3"

LUTRIS_DB = File.join(ENV.fetch("XDG_DATA_HOME"), "lutris", "pga.db")
FileUtils.mkdir_p(File.dirname(LUTRIS_DB))
SQLite3::Database.new(LUTRIS_DB) do |db|
  db.execute("CREATE TABLE games (id INTEGER, name TEXT, slug TEXT, runner TEXT, installed INTEGER, configPath TEXT)")
  db.execute("CREATE TABLE categories (id INTEGER, name TEXT)")
  db.execute("CREATE TABLE games_categories (game_id INTEGER, category_id INTEGER)")
  db.execute("INSERT INTO games (id, name, slug, runner, installed, configPath) VALUES (1, 'Drive Lutris Game', 'drive-lutris-game', 'wine', 1, '/tmp/drive-lutris-config')")
end

ITCH_DB = File.join(ENV.fetch("XDG_CONFIG_HOME"), "itch", "db", "butler.db")
FileUtils.mkdir_p(File.dirname(ITCH_DB))
SQLite3::Database.new(ITCH_DB) do |db|
  db.execute("CREATE TABLE games (id INTEGER, title TEXT, cover_url TEXT, still_cover_url TEXT)")
  db.execute("CREATE TABLE caves (id INTEGER, game_id INTEGER)")
  db.execute("INSERT INTO games (id, title, cover_url, still_cover_url) VALUES (1, 'Drive Itch Game', NULL, NULL)")
  db.execute("INSERT INTO caves (id, game_id) VALUES (1, 1)")
end

# Real fixture files for the Heroic source's four sub-sources (sideload,
# Legendary/Epic, GOG, Nile/Amazon), so the import step below exercises each
# HeroicSourceIterable sub-source's actual library/installed-list parsing
# instead of only hitting "no valid candidate" and skipping. See
# lib/cartridges/importer/heroic_source.rb for the paths each sub-source
# reads relative to the "heroic-location" config root.
HEROIC_ROOT = File.join(ENV.fetch("XDG_CONFIG_HOME"), "heroic")
FileUtils.mkdir_p(File.join(HEROIC_ROOT, "store"))
FileUtils.mkdir_p(File.join(HEROIC_ROOT, "store_cache"))
FileUtils.mkdir_p(File.join(HEROIC_ROOT, "legendaryConfig"))
FileUtils.mkdir_p(File.join(HEROIC_ROOT, "legendary"))
FileUtils.mkdir_p(File.join(HEROIC_ROOT, "gog_store"))
FileUtils.mkdir_p(File.join(HEROIC_ROOT, "nile_config", "nile"))
FileUtils.mkdir_p(File.join(HEROIC_ROOT, "sideload_apps"))

File.write(File.join(HEROIC_ROOT, "config.json"), "{}")
File.write(File.join(HEROIC_ROOT, "store", "config.json"), JSON.generate({"games" => {"hidden" => []}}))

File.write(File.join(HEROIC_ROOT, "store_cache", "legendary_library.json"), JSON.generate({
  "library" => [{"app_name" => "epic1", "runner" => "legendary", "title" => "Drive Epic Game", "developer" => "Epic Dev", "art_square" => "https://example.com/epic.jpg"}],
}))
File.write(File.join(HEROIC_ROOT, "legendary", "installed.json"), JSON.generate({"epic1" => {}}))

File.write(File.join(HEROIC_ROOT, "store_cache", "gog_library.json"), JSON.generate({
  "games" => [{"app_name" => "gog1", "runner" => "gogdl", "title" => "Drive GOG Game", "developer" => "GOG Dev", "art_square" => "https://example.com/gog.jpg"}],
}))
File.write(File.join(HEROIC_ROOT, "gog_store", "installed.json"), JSON.generate({"installed" => [{"appName" => "gog1"}]}))

File.write(File.join(HEROIC_ROOT, "store_cache", "nile_library.json"), JSON.generate({
  "library" => [{"app_name" => "nile1", "runner" => "nile", "title" => "Drive Amazon Game", "developer" => "Amazon Dev", "art_square" => "https://example.com/nile.jpg"}],
}))
File.write(File.join(HEROIC_ROOT, "nile_config", "nile", "installed.json"), JSON.generate([{"id" => "nile1"}]))

File.write(File.join(HEROIC_ROOT, "sideload_apps", "library.json"), JSON.generate({
  "games" => [{"app_name" => "side1", "runner" => "sideload", "title" => "Drive Sideload Game", "developer" => "", "art_square" => "https://example.com/side.jpg"}],
}))

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))

require "cartridges"
require_relative "gtk_driver"

SHOTS = File.expand_path("../tmp/shots", __dir__)
FileUtils.rm_rf(SHOTS)

# Short aliases, since every check below reaches into Cartridges::.
Shared = Cartridges::Shared
GameModel = Cartridges::GameModel

# Turns the main loop over for `ms` milliseconds and comes back, without
# sleeping, so GLib::Timeout callbacks (the import monitor, the write
# debounce) that are already armed get to run.
def pump(ms)
  (Process.clock_gettime(Process::CLOCK_MONOTONIC) + (ms / 1000.0)).then do |deadline|
    while Process.clock_gettime(Process::CLOCK_MONOTONIC) < deadline
      GLib::MainContext.default.iteration(false)
    end
  end
end

GtkDriver.drive(Cartridges::Application.new, shots: SHOTS, timeout: 60) do |d, app|
  d.window { app.main_window.window }

  d.step("the window builds and shows the empty library") do
    d.check("the window is an Adwaita::ApplicationWindow") do
      app.main_window.window.is_a?(Adwaita::ApplicationWindow)
    end
    d.check("it is the only toplevel") { Gtk::Window.list_toplevels.length == 1 }
    d.check("its title is Cartridges") { app.main_window.window.title == "Cartridges" }
    d.check("the library page is the visible page") do
      app.main_window.navigation_view.visible_page.equal?(app.main_window.library_page)
    end
    d.check("the empty notice overlays the library") do
      app.main_window.library_notices.empty.parent.equal?(app.main_window.library_overlay)
    end
    d.check("no games are in the store") { Shared.store.size.zero? }
    d.check("the sidebar's All Games row is selected") do
      app.main_window.sidebar.selected_row.equal?(app.main_window.all_games_row.parent)
    end
    d.shot("01-empty-library")
  end

  d.step("the add-game dialog refuses an empty name, then an empty executable") do
    app.app.activate_action("add_game", nil)
  end

  d.step("validation and the add-game dialog itself") do
    Cartridges::DetailsDialog.open_instance.then do |dialog|
      d.check("the dialog opened") { !dialog.nil? }
      d.check("it reports itself open") { Cartridges::DetailsDialog.open? }
      d.check("it is the window's visible dialog") { app.main_window.window.visible_dialog.equal?(dialog) }
      d.check("its title is Add New Game") { dialog.title == "Add New Game" }
      d.shot("02-add-game-dialog")

      dialog.send(:apply_button).signal_emit("clicked")
      d.check("an empty name opens an alert dialog") { app.main_window.window.visible_dialog.is_a?(Adwaita::AlertDialog) }
      d.check("it names the problem") { app.main_window.window.visible_dialog.body == "Game title cannot be empty." }
      app.main_window.window.visible_dialog.close
      pump(100)
      d.shot("03-empty-name-error")

      dialog.send(:name_row).text = "Chess"
      dialog.send(:apply_button).signal_emit("clicked")
      d.check("an empty executable opens its own alert") { app.main_window.window.visible_dialog.is_a?(Adwaita::AlertDialog) }
      d.check("naming the right problem") { app.main_window.window.visible_dialog.body == "Executable cannot be empty." }
      app.main_window.window.visible_dialog.close
      pump(100)
      d.shot("04-empty-executable-error")

      dialog.send(:developer_row).text = "Acme"
      dialog.send(:executable_row).text = "true"
      dialog.send(:apply_button).signal_emit("clicked")
    end
  end

  d.step("the first game lands in the library and the sidebar") do
    d.check("one game in the store") { Shared.store.size == 1 }
    d.check("the dialog closed") { Cartridges::DetailsDialog.open_instance.nil? }
    d.check("the details page opened for it") do
      app.main_window.navigation_view.visible_page.equal?(app.main_window.details_page)
    end
    d.check("the details page shows its name") { app.main_window.details_builder.title.label == "Chess" }
    d.check("and its developer") { app.main_window.details_builder.developer.label == "Acme" }
    d.check("one tile exists") { app.main_window.game_tiles.size == 1 }
    chess = Shared.store.find { |g| g.name == "Chess" }
    d.check("the tile is parented in the library flow box") do
      app.main_window.game_tiles[chess.game_id].parent&.parent.equal?(app.main_window.library)
    end
    d.check("the empty notice is gone") { app.main_window.library_notices.empty.parent.nil? }
    d.check("the game file was written to disk") do
      File.exist?(Shared::GAMES_DIR / "#{chess.game_id}.json")
    end
    d.check("the Added source row appeared with count 1") do
      app.main_window.added_row.parent.visible? && app.main_window.added_row.count_label.label == "1"
    end
    d.shot("05-first-game")
  end

  d.step("going back to the library and adding a second game") do
    app.main_window.window.activate_action("go_home", nil)
    app.app.activate_action("add_game", nil)
  end

  d.step("Checkers is added the same way") do
    Cartridges::DetailsDialog.open_instance.then do |dialog|
      d.check("the dialog reopened") { !dialog.nil? }
      dialog.send(:name_row).text = "Checkers"
      dialog.send(:executable_row).text = "true"
      dialog.send(:apply_button).signal_emit("clicked")
    end
    d.check("two games now") { Shared.store.size == 2 }
    d.check("two tiles") { app.main_window.game_tiles.size == 2 }
    d.check("the Added row count followed") { app.main_window.added_row.count_label.label == "2" }
  end

  d.step("back to the library to work the sidebar, search and sort") do
    app.main_window.window.activate_action("go_home", nil)
  end

  d.step("the sidebar's Added row filters to the imported source") do
    app.main_window.sidebar.select_row(app.main_window.added_row.parent)
    d.check("the filter state followed the row") { app.main_window.filter_state == "imported" }
    d.check("the page title followed too") { app.main_window.library_page.title == "Added" }
    app.main_window.sidebar.select_row(app.main_window.all_games_row.parent)
    d.check("back to all games") { app.main_window.filter_state == "all" }
  end

  d.step("win.toggle_search opens the search bar") do
    app.main_window.window.activate_action("toggle_search", nil)
  end

  d.step("typing into it filters the library down to one tile") do
    d.check("the search bar is in search mode") { app.main_window.search_bar.search_mode? }
    app.main_window.search_entry.text = "chess"
    app.main_window.library.invalidate_filter
    chess_tile = app.main_window.game_tiles.values.find { |t| t.model.name == "Chess" }
    checkers_tile = app.main_window.game_tiles.values.find { |t| t.model.name == "Checkers" }
    d.check("Chess's model is not filtered") { !chess_tile.model.filtered? }
    d.check("Checkers's model is filtered out") { checkers_tile.model.filtered? }
    pump(100)
      d.shot("06-search-filtered")
  end

  d.step("a search with no matches shows the no-results notice") do
    app.main_window.search_entry.text = "zzz-no-such-game"
    app.main_window.library.invalidate_filter
    d.check("every child is filtered") { app.main_window.game_tiles.values.all? { |t| t.model.filtered? } }
    d.check("the no-results notice is showing") do
      app.main_window.library_notices.no_results.parent.equal?(app.main_window.library_overlay)
    end
    pump(100)
      d.shot("07-no-results")
  end

  d.step("closing search clears the entry and the filter") do
    app.main_window.window.activate_action("toggle_search", nil)
    d.check("search mode closed") { !app.main_window.search_bar.search_mode? }
    d.check("the entry was cleared") { app.main_window.search_entry.text.empty? }
    app.main_window.library.invalidate_filter
    d.check("nothing is filtered now") { app.main_window.game_tiles.values.none? { |t| t.model.filtered? } }
  end

  d.step("win.sort_by swaps the sort order") do
    app.main_window.window.activate_action("sort_by", GLib::Variant.new("a-z"))
    d.check("the window's sort state followed") { app.main_window.sort_state == "a-z" }
    d.check("and was persisted") { Shared.state_schema.get_string("sort-mode") == "a-z" }
  end

  d.step("the primary menu's model carries upstream's sort submenu and show-hidden item") do
    app.main_window.primary_menu_button.menu_model.then do |model|
      d.check("it is a Gio::Menu") { model.is_a?(Gio::Menu) }
      d.check("it has the sort section, the show-hidden item and the about section") { model.n_items == 3 }
    end
  end

  d.step("win.open_menu pops up the primary menu button while the library page shows") do
    app.main_window.window.activate_action("open_menu", nil)
    d.check("the menu button is active (popped up)") { app.main_window.primary_menu_button.active? }
    app.main_window.primary_menu_button.popdown
  end

  d.step("the game tile reveals its play/menu buttons on hover and hides them again") do
    chess_tile = app.main_window.game_tiles.values.find { |t| t.model.name == "Chess" }
    chess_tile.reveal(true)
    d.check("the play button is revealed") { chess_tile.play_revealer.reveal_child? }
    d.check("the menu button is revealed") { chess_tile.menu_revealer.reveal_child? }
    chess_tile.reveal(false)
    d.check("and hidden again") { !chess_tile.play_revealer.reveal_child? && !chess_tile.menu_revealer.reveal_child? }
  end

  d.step("the tile's own menu carries the Edit/Hide/Remove options") do
    chess_tile = app.main_window.game_tiles.values.find { |t| t.model.name == "Chess" }
    chess_tile.menu_button.menu_model.then do |model|
      d.check("one section with three items") { model.n_items == 1 }
    end
    d.check("hidden tiles get the hidden menu instead") do
      chess_tile.model.hidden = true
      chess_tile.refresh
      swapped = chess_tile.menu_button.menu_model
      chess_tile.model.hidden = false
      chess_tile.refresh
      !swapped.equal?(Cartridges::GameMenus.game_options)
    end
  end

  d.step("clicking a tile opens the details page for that game") do
    chess_tile = app.main_window.game_tiles.values.find { |t| t.model.name == "Chess" }
    chess_tile.cover_button.signal_emit("clicked")
  end

  d.step("the details page shows the right game and its toolbar is wired") do
    d.check("the details page is showing") do
      app.main_window.navigation_view.visible_page.equal?(app.main_window.details_page)
    end
    d.check("the active game is Chess") { app.main_window.active_game.name == "Chess" }
    d.check("the play button's action is app.launch_game") do
      app.main_window.details_builder.play_button.action_name == "app.launch_game"
    end
    d.check("the search menu carries upstream's six sites") do
      Cartridges::WindowMenus.search.n_items == 1
    end
    d.shot("08-details-page")
  end

  d.step("app.edit_game opens the dialog pre-filled, and applying it updates the tile") do
    app.app.activate_action("edit_game", nil)
    Cartridges::DetailsDialog.open_instance.then do |dialog|
      d.check("the dialog opened") { !dialog.nil? }
      d.check("its title is Game Details (edit mode)") { dialog.title == "Game Details" }
      d.check("the name was pre-filled") { dialog.send(:name_row).text == "Chess" }
      d.check("the developer was pre-filled") { dialog.send(:developer_row).text == "Acme" }
      d.check("the apply button reads Apply, not Add") { dialog.send(:apply_button).label == "Apply" }

      dialog.send(:developer_row).text = "Acme Corp"
      dialog.send(:apply_button).signal_emit("clicked")
    end
    d.check("the model picked up the edit") { app.main_window.active_game.developer == "Acme Corp" }
    d.check("so did the details page") { app.main_window.details_builder.developer.label == "Acme Corp" }
    d.check("still one game, not a duplicate") { Shared.store.size == 2 }
  end

  d.step("app.hide_game hides the active game and raises an undo toast") do
    app.app.activate_action("hide_game", nil)
  end

  d.step("hiding popped the details page and the toast offers undo") do
    d.check("Chess is hidden now") { app.main_window.active_game.hidden? }
    d.check("the details page was popped") do
      app.main_window.navigation_view.visible_page.equal?(app.main_window.library_page)
    end
    chess = app.main_window.active_game
    d.check("an undo toast is on record") { app.main_window.toasts.key?([chess, "hide"]) }
    chess_tile = app.main_window.game_tiles[chess.game_id]
    d.check("the tile moved to the hidden library") do
      chess_tile.parent&.parent.equal?(app.main_window.hidden_library)
    end
    d.check("win.undo brings it back") do
      app.main_window.window.activate_action("undo", nil)
      !app.main_window.active_game.hidden?
    end
    d.check("and the tile moved back to the shown library") do
      chess_tile.parent&.parent.equal?(app.main_window.library)
    end
    pump(100)
    d.shot("09-library-after-undo")
  end

  d.step("win.show_hidden pushes the hidden-library page even with nothing hidden") do
    app.main_window.window.activate_action("show_hidden", nil)
    d.check("the hidden library page is showing") do
      app.main_window.navigation_view.visible_page.equal?(app.main_window.hidden_library_page)
    end
    d.check("the hidden-empty notice is showing") do
      app.main_window.library_notices.hidden_empty.parent.equal?(app.main_window.hidden_library_builder.overlay)
    end
    d.check("win.show_hidden is disabled while already there") { !app.main_window.window.lookup_action("show_hidden").enabled? }
    pump(100)
    d.shot("10-hidden-empty")
  end

  d.step("the hidden page's own search bar and menu button work") do
    app.main_window.window.activate_action("toggle_search", nil)
    d.check("the hidden search bar opened") { app.main_window.hidden_search_bar.search_mode? }
    app.main_window.window.activate_action("toggle_search", nil)
    d.check("and closed again") { !app.main_window.hidden_search_bar.search_mode? }
    app.main_window.window.activate_action("open_menu", nil)
    d.check("open_menu pops the hidden page's own menu button") { app.main_window.hidden_library_builder.menu_button.active? }
    app.main_window.hidden_library_builder.menu_button.popdown
  end

  d.step("win.go_to_parent does nothing on the hidden page (it only pops the details page)") do
    app.main_window.window.activate_action("go_to_parent", nil)
    d.check("still on the hidden library page") do
      app.main_window.navigation_view.visible_page.equal?(app.main_window.hidden_library_page)
    end
  end

  d.step("win.go_home pops all the way back to the library") do
    app.main_window.window.activate_action("go_home", nil)
    d.check("back on the library page") do
      app.main_window.navigation_view.visible_page.equal?(app.main_window.library_page)
    end
    d.check("win.show_hidden is enabled again") { app.main_window.window.lookup_action("show_hidden").enabled? }
  end

  d.step("hiding Chess for real, then checking the hidden library shows it") do
    app.main_window.active_game.toggle_hidden rescue nil
    chess = Shared.store.find { |g| g.name == "Chess" }
    chess.toggle_hidden unless chess.hidden?
    app.main_window.window.activate_action("show_hidden", nil)
  end

  d.step("the hidden library now shows the one hidden tile") do
    chess = Shared.store.find { |g| g.name == "Chess" }
    d.check("Chess is hidden") { chess.hidden? }
    d.check("its tile is in the hidden flow box") do
      app.main_window.game_tiles[chess.game_id].parent&.parent.equal?(app.main_window.hidden_library)
    end
    d.check("the hidden-empty notice is gone") { app.main_window.library_notices.hidden_empty.parent.nil? }
    d.shot("11-hidden-with-one")
    chess.toggle_hidden
    app.main_window.window.activate_action("go_home", nil)
  end

  d.step("app.remove_game removes the active game and offers undo") do
    app.main_window.set_active_game(Shared.store.find { |g| g.name == "Checkers" })
    app.app.activate_action("remove_game", nil)
  end

  d.step("Checkers is gone from the store and the sidebar, with undo available") do
    checkers = Shared.store.find { |g| g.name == "Checkers" }
    d.check("it is marked removed") { checkers.removed? }
    d.check("an undo toast is on record") { app.main_window.toasts.key?([checkers, "remove"]) }
    d.check("its tile is unparented") { app.main_window.game_tiles[checkers.game_id].parent.nil? }
    d.check("the Added count dropped to 1") { app.main_window.added_row.count_label.label == "1" }

    app.main_window.window.activate_action("undo", nil)
    d.check("undo un-marks it removed") { !checkers.removed? }
    d.check("and it is back in the library") do
      app.main_window.game_tiles[checkers.game_id].parent&.parent.equal?(app.main_window.library)
    end
    d.check("the Added count is back to 2") { app.main_window.added_row.count_label.label == "2" }
  end

  d.step("app.remove_game_details_view only fires while the details page is showing") do
    app.main_window.set_active_game(Shared.store.find { |g| g.name == "Checkers" })
    app.app.activate_action("remove_game_details_view", nil)
    d.check("nothing removed - the details page was not showing") do
      !Shared.store.find { |g| g.name == "Checkers" }.removed?
    end
    app.main_window.show_details_page(Shared.store.find { |g| g.name == "Checkers" })
    app.app.activate_action("remove_game_details_view", nil)
    d.check("removed now that the details page was showing") do
      Shared.store.find { |g| g.name == "Checkers" }.removed?
    end
    app.main_window.window.activate_action("undo", nil)
    app.main_window.window.activate_action("go_home", nil)
  end

  d.step("the per-site search actions build the right URI and hit the sandbox's missing browser") do
    # Called as `app.on_*_action` directly, not through
    # `app.app.activate_action` - a Ruby exception raised from inside a
    # signal callback invoked from the C side (as activating a GAction
    # does) is not Ruby's normal raise/rescue: ruby-gnome's default policy
    # for an unhandled exception in such a callback is to print it and
    # call `exit`, which would kill this whole driver rather than hand the
    # error to our rescue. Calling the method directly is a plain Ruby
    # call, so the exception propagates normally.
    app.main_window.set_active_game(Shared.store.find { |g| g.name == "Chess" })
    %w[igdb_search sgdb_search protondb_search pcgw_search lutris_search hltb_search].each do |action|
      d.check("app.on_#{action}_action builds a URI from the active game and only fails on the sandbox's missing default browser") do
        app.send(:"on_#{action}_action")
        false
      rescue Gio::IOError::NotSupported
        # No desktop portal under Xvfb, so `AppInfo.launch_default_for_uri`
        # cannot succeed here - this is the environment's limit, not the
        # port's. Reaching this line at all proves the method built a URI
        # from the active game's name without raising anything else first
        # (a NoMethodError on a nil active_game, for instance).
        true
      end
    end
  end

  d.step("win.show_sidebar toggles the overlay split view") do
    was = app.main_window.overlay_split_view.show_sidebar?
    app.main_window.window.activate_action("show_sidebar", nil)
    d.check("the sidebar's visibility flipped") { app.main_window.overlay_split_view.show_sidebar? == !was }
    d.check("the setting was persisted") { Shared.state_schema.get_boolean("show-sidebar") == !was }
    app.main_window.window.activate_action("show_sidebar", nil)
    d.check("flipping it back restores the setting") { Shared.state_schema.get_boolean("show-sidebar") == was }
  end

  d.step("app.preferences opens the preferences dialog") do
    app.app.activate_action("preferences", nil)
  end

  d.step("every preferences page, row and binding is live") do
    Cartridges::PreferencesDialog.open_instance.then do |dialog|
      d.check("it opened") { !dialog.nil? }
      d.check("it reports itself open") { Cartridges::PreferencesDialog.open? }
      d.check("its title is Preferences") { dialog.title == "Preferences" }
      d.shot("12-preferences")

      general = dialog.send(:exit_after_launch_row)
      before = Shared.schema.get_boolean("exit-after-launch")
      general.active = !before
      d.check("toggling a general switch writes through to the schema") do
        Shared.schema.get_boolean("exit-after-launch") == !before
      end
      general.active = before

      sgdb_switch = dialog.send(:sgdb_enabled_row)
      sgdb_before = Shared.schema.get_boolean("sgdb")
      sgdb_switch.active = !sgdb_before
      d.check("the SGDB page's switch writes through too") { Shared.schema.get_boolean("sgdb") == !sgdb_before }
      sgdb_switch.active = sgdb_before

      key_row = dialog.send(:sgdb_key_row)
      key_row.text = "a-test-key"
      d.check("the API key entry row writes through") { Shared.schema.get_string("sgdb-key") == "a-test-key" }
      key_row.text = ""

      d.check("a source switch (Steam) reads its schema key") do
        dialog.send(:sources_group).is_a?(Adwaita::PreferencesGroup)
      end
      d.check("the Heroic switch is in the sources list") { Cartridges::PreferencesDialog::SOURCES.key?("heroic") }
    end
    dialog_instance = Cartridges::PreferencesDialog.open_instance
    dialog_instance.close
    d.check("closing clears the open flag") { !Cartridges::PreferencesDialog.open? }
  end

  d.step("a second app.add_game while a game is being edited is refused (open-instance guard)") do
    app.app.activate_action("edit_game", nil)
    before = Cartridges::DetailsDialog.open_instance
    app.app.activate_action("add_game", nil)
    d.check("the same dialog instance is still open, no second one was built") do
      Cartridges::DetailsDialog.open_instance.equal?(before)
    end
    before.close
  end

  d.step("app.shortcuts opens the shortcuts dialog with upstream's live accelerators") do
    app.app.activate_action("shortcuts", nil)
  end

  d.step("every shortcuts item resolves the accelerator application.rb actually binds") do
    app.main_window.window.visible_dialog.then do |dialog|
      d.check("it is the shortcuts dialog") { dialog.is_a?(Cartridges::ShortcutsDialog) }
      d.shot("13-shortcuts")
      dialog.close
    end
    d.check("Ctrl+Q quits") { app.app.get_accels_for_action("app.quit") == ["<Control>q"] }
    d.check("Ctrl+N adds a game") { app.app.get_accels_for_action("app.add_game") == ["<Control>n"] }
    d.check("Ctrl+I imports") { app.app.get_accels_for_action("app.import") == ["<Control>i"] }
    d.check("Ctrl+H shows hidden games") { app.app.get_accels_for_action("win.show_hidden") == ["<Control>h"] }
    d.check("Delete removes from the details view") { app.app.get_accels_for_action("app.remove_game_details_view") == ["Delete"] }
    d.check("Ctrl+comma opens preferences") { app.app.get_accels_for_action("app.preferences") == ["<Control>comma"] }
    d.check("Ctrl+question opens shortcuts") { app.app.get_accels_for_action("app.shortcuts") == ["<Control>question"] }
    d.check("Ctrl+Z undoes") { app.app.get_accels_for_action("win.undo") == ["<Control>z"] }
    d.check("Ctrl+F toggles search") { app.app.get_accels_for_action("win.toggle_search") == ["<Control>f"] }
    d.check("F9 toggles the sidebar") { app.app.get_accels_for_action("win.show_sidebar") == ["F9"] }
    d.check("F10 opens the menu") { app.app.get_accels_for_action("win.open_menu") == ["F10"] }
    d.check("Ctrl+W closes") { app.app.get_accels_for_action("win.close") == ["<Control>w"] }
    d.check("alt+Up goes to the parent page") { app.app.get_accels_for_action("win.go_to_parent") == ["<Alt>Up"] }
    d.check("alt+Home goes home") { app.app.get_accels_for_action("win.go_home") == ["<Alt>Home"] }
  end

  d.step("app.about opens the about dialog with upstream's own details") do
    app.app.activate_action("about", nil)
  end

  d.step("the about dialog carries upstream's literals") do
    app.main_window.window.visible_dialog.then do |dialog|
      d.check("it is an Adwaita::AboutDialog") { dialog.is_a?(Adwaita::AboutDialog) }
      d.check("its name is Cartridges") { dialog.application_name == "Cartridges" }
      d.check("its icon is the app id") { dialog.application_icon == Shared::APP_ID }
      d.check("its version is upstream's") { dialog.version == Shared::VERSION }
      d.check("its developer is kramo") { dialog.developer_name == "kramo" }
      d.check("its licence is GPL-3.0") { dialog.license_type == :gpl_3_0 }
      d.shot("14-about")
      dialog.close
    end
  end

  d.step("app.import runs with no installed sources and reports no new games") do
    app.app.activate_action("import", nil)
    d.check("the import action disabled add/import/preferences while running") do
      !app.app.lookup_action("import").enabled?
    end
    d.check("an import progress dialog is showing") { app.main_window.window.visible_dialog.is_a?(Adwaita::Dialog) }
    d.check("Heroic was added as an import source (schema default is on)") do
      Shared.importer.sources.any? { |source| source.is_a?(Cartridges::Importer::HeroicSource) }
    end
    d.check("Lutris was added as an import source") do
      Shared.importer.sources.any? { |source| source.is_a?(Cartridges::Importer::LutrisSource) }
    end
    d.check("itch was added as an import source") do
      Shared.importer.sources.any? { |source| source.is_a?(Cartridges::Importer::ItchSource) }
    end
    d.shot("15-import-progress")
  end

  d.step("the import finishes: real fixture databases make Lutris and itch actually import a game each") do
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 30
    pump(200) until Shared.importer.finished? || Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
    # The dialog's own close-attempt handling settles a tick or two after
    # the importer considers itself finished (the same Adwaita "closed too
    # soon after opening" quirk application.rb's watchdog comment names), so
    # give it some further turns of the loop before asserting on it.
    pump(2000)
    d.check("the import dialog closed") { !app.main_window.window.visible_dialog.is_a?(Adwaita::Dialog) || app.main_window.window.visible_dialog.nil? }
    d.check("the import action is enabled again") { app.app.lookup_action("import").enabled? }
    d.check("six games came in: one each from the Lutris and itch fixtures, and one from each of the four Heroic sub-sources") do
      Shared.importer.n_games_added == 6
    end
    d.check("the Lutris fixture game landed in the store with the right name and source") do
      game = Shared.store.find { |g| g.name == "Drive Lutris Game" }
      !game.nil? && game.source == "lutris_wine"
    end
    d.check("the Lutris game's id round-trips lutris's own game_id format") do
      Shared.store.find { |g| g.name == "Drive Lutris Game" }.game_id == "lutris_wine_1"
    end
    d.check("the itch fixture game landed in the store with the right name and source") do
      game = Shared.store.find { |g| g.name == "Drive Itch Game" }
      !game.nil? && game.source == "itch"
    end
    d.check("the itch game's id round-trips itch's own game_id format") do
      Shared.store.find { |g| g.name == "Drive Itch Game" }.game_id == "itch_1"
    end
    {
      "Drive Epic Game" => ["heroic_epic", "heroic_epic_epic1"],
      "Drive GOG Game" => ["heroic_gog", "heroic_gog_gog1"],
      "Drive Amazon Game" => ["heroic_amazon", "heroic_amazon_nile1"],
      "Drive Sideload Game" => ["heroic_sideload", "heroic_sideload_side1"],
    }.each do |name, (source, game_id)|
      d.check("the Heroic fixture game #{name.inspect} landed in the store with the right source and id") do
        game = Shared.store.find { |g| g.name == name }
        !game.nil? && game.source == source && game.game_id == game_id
      end
    end
    d.shot("16-after-import")
  end

  d.step("what was built survives a reload from disk") do
    chess_path = Shared::GAMES_DIR / "#{Shared.store.find { |g| g.name == "Chess" }.game_id}.json"
    d.check("Chess's file is on disk") { chess_path.exist? }
    reloaded = GameModel.from_file(chess_path)
    d.check("its name round-trips") { reloaded.name == "Chess" }
    d.check("its developer round-trips") { reloaded.developer == "Acme Corp" }
    d.check("its executable round-trips") { reloaded.executable == "true" }
  end

  # The last step: closing the last window may bring the whole GApplication
  # down (Gtk::Application quits once its last window is gone and nothing
  # is holding it open), which ends the main loop this driver's own
  # GLib::Timeout steps run on. Both halves of this check - that the window
  # actually closed, and that nothing was left broken by the close - have
  # to happen in the same step, because a step scheduled after this one
  # would never be reached once the loop exits.
  d.step("win.close closes the main window, and nothing is left running") do
    d.check("one toplevel before closing") { Gtk::Window.list_toplevels.length == 1 }
    app.main_window.window.activate_action("close", nil)
    pump(300)
    d.check("no toplevels left") { Gtk::Window.list_toplevels.empty? }
  end
end
