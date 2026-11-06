# frozen_string_literal: true

require "adwaita"
require_relative "shared"
require_relative "source_row"
require_relative "library_notices"
require_relative "window_menus"
require_relative "hidden_library_page"
require_relative "details_page"
require_relative "relative_date"

module Cartridges
  # Window is the main window: a split view with the source sidebar and
  # library in a navigation page, the hidden library and the game details
  # page reachable by pushing onto the same Adw.NavigationView.
  #
  # Ported from cartridges/window.py and data/gtk/window.blp. DisplayManager
  # (lib/cartridges/store/managers/display_manager.rb) is the one that moves
  # a GameTile in and out of `library`/`hidden_library`; this class owns the
  # chrome around them.
  class Window
    attr_reader :application, :game_tiles, :game_covers, :toasts, :source_rows
    attr_accessor :active_game, :sort_state, :filter_state

    def initialize(application)
      @application = application
      @game_tiles = {}
      @game_covers = {}
      @toasts = {}
      @source_rows = {}
      @sort_state = "last_played"
      @filter_state = "all"
      @details_view_game_cover = nil
    end

    def build
      window.tap do |win|
        win.content = toast_overlay

        toast_overlay.tap do |to|
          to.child = navigation_view

          navigation_view.tap do |nv|
            nv.add(library_page)
            nv.signal_connect("popped") { |*_args| set_show_hidden }
            nv.signal_connect("pushed") { |*_args| set_show_hidden }
          end
        end
      end

      library.set_filter_func { |child| filter_func(child) }
      hidden_library_builder.library.set_filter_func { |child| filter_func(child) }
      library.set_sort_func { |a, b| sort_func(a, b) }
      hidden_library_builder.library.set_sort_func { |a, b| sort_func(a, b) }

      connect_signals
      bind_library_rows
      set_library_child
      sidebar.select_row(all_games_row.parent)

      window
    end

    # --- Window chrome -------------------------------------------------

    def window
      @window ||= Adwaita::ApplicationWindow.new(@application).tap do |win|
        win.title = "Cartridges"
        win.width_request = 360
        win.height_request = 100
      end
    end

    def toast_overlay = @toast_overlay ||= Adwaita::ToastOverlay.new

    def navigation_view = @navigation_view ||= Adwaita::NavigationView.new

    def library_page = @library_page ||= Adwaita::NavigationPage.new(overlay_split_view, "All Games")

    def overlay_split_view
      @overlay_split_view ||= Adwaita::OverlaySplitView.new.tap do |sv|
        sv.sidebar_width_fraction = 0.2
        sv.sidebar = sidebar_page
        sv.content = library_toolbar_view
        sv.show_sidebar = Shared.state_schema.get_boolean("show-sidebar")
      end
    end

    # --- Sidebar --------------------------------------------------------

    def sidebar_page = @sidebar_page ||= Adwaita::NavigationPage.new(sidebar_toolbar_view, "Cartridges")

    def sidebar_toolbar_view
      @sidebar_toolbar_view ||= Adwaita::ToolbarView.new.tap do |view|
        view.add_top_bar(sidebar_header_bar)
        view.content = sidebar_scrolled_window
      end
    end

    def sidebar_header_bar
      @sidebar_header_bar ||= Adwaita::HeaderBar.new.tap do |hb|
        hb.pack_start(show_sidebar_toggle)
      end
    end

    def show_sidebar_toggle
      @show_sidebar_toggle ||= Gtk::Button.new.tap do |btn|
        btn.icon_name = "sidebar-show-symbolic"
        btn.action_name = "win.show_sidebar"
        btn.tooltip_text = "Toggle Sidebar"
      end
    end

    def sidebar_scrolled_window
      @sidebar_scrolled_window ||= Gtk::ScrolledWindow.new.tap do |sw|
        sw.hscrollbar_policy = :never
        sw.child = sidebar
      end
    end

    def sidebar
      @sidebar ||= Gtk::ListBox.new.tap do |list|
        list.add_css_class("navigation-sidebar")
        list.append(all_games_row)
        list.append(added_row)
        list.append(imported_heading_row)
        list.signal_connect("row-selected") { |_widget, row| row_selected(row) }
      end
    end

    def all_games_row
      @all_games_row ||= SourceRow.new("all", "All Games", 0).tap do |row|
        row.icon.icon_name = "view-grid-symbolic"
      end
    end

    def added_row
      @added_row ||= SourceRow.new("imported", "Added", 0)
    end

    def imported_heading_row
      @imported_heading_row ||= Gtk::ListBoxRow.new.tap do |row|
        row.selectable = false
        row.activatable = false
        row.child = Gtk::Label.new.tap do |label|
          label.label = "Imported"
          label.halign = :start
          label.add_css_class("heading")
        end
      end
    end

    # --- Library ----------------------------------------------------------

    def library_toolbar_view
      @library_toolbar_view ||= Adwaita::ToolbarView.new.tap do |view|
        view.add_top_bar(library_header_bar)
        view.add_top_bar(search_bar)
        view.content = library_overlay
      end
    end

    def library_header_bar
      @library_header_bar ||= Adwaita::HeaderBar.new.tap do |hb|
        hb.pack_start(show_sidebar_button)
        hb.pack_start(add_game_menu_button)
        hb.pack_end(primary_menu_button)
        hb.pack_end(search_button)
      end
    end

    def show_sidebar_button
      @show_sidebar_button ||= Gtk::Button.new.tap do |btn|
        btn.icon_name = "sidebar-show-symbolic"
        btn.action_name = "win.show_sidebar"
        btn.tooltip_text = "Toggle Sidebar"
      end
    end

    def add_game_menu_button
      @add_game_menu_button ||= Gtk::MenuButton.new.tap do |btn|
        btn.tooltip_text = "Add Game"
        btn.icon_name = "list-add-symbolic"
        btn.menu_model = WindowMenus.add_games
      end
    end

    def primary_menu_button
      @primary_menu_button ||= Gtk::MenuButton.new.tap do |btn|
        btn.tooltip_text = "Main Menu"
        btn.icon_name = "open-menu-symbolic"
        btn.menu_model = WindowMenus.primary_menu
      end
    end

    def search_button
      @search_button ||= Gtk::ToggleButton.new.tap do |btn|
        btn.tooltip_text = "Search"
        btn.icon_name = "system-search-symbolic"
        btn.action_name = "win.toggle_search"
      end
    end

    def search_bar
      @search_bar ||= Gtk::SearchBar.new.tap do |bar|
        bar.child = search_entry
        bar.connect_entry(search_entry)
        bar.key_capture_widget = navigation_view
      end
    end

    def search_entry
      @search_entry ||= Gtk::SearchEntry.new.tap do |entry|
        entry.placeholder_text = "Search"
        entry.hexpand = true
      end
    end

    def library_overlay = @library_overlay ||= Gtk::Overlay.new.tap { |o| o.child = library_scrolled_window }

    def library_scrolled_window
      @library_scrolled_window ||= Gtk::ScrolledWindow.new.tap { |sw| sw.child = library }
    end

    def library
      @library ||= Gtk::FlowBox.new.tap do |flow|
        flow.homogeneous = true
        flow.halign = :center
        flow.valign = :start
        flow.column_spacing = 12
        flow.row_spacing = 12
        flow.margin_top = 15
        flow.margin_bottom = 15
        flow.margin_start = 15
        flow.margin_end = 15
        flow.selection_mode = :none
        flow.add_css_class("no-hover")
      end
    end

    # --- Hidden library / details, as separate navigation pages ----------

    def hidden_library_builder = @hidden_library_builder ||= HiddenLibraryPage.new
    def hidden_library_page = @hidden_library_page ||= hidden_library_builder.build
    def hidden_library = hidden_library_builder.library
    def hidden_search_entry = hidden_library_builder.search_entry
    def hidden_search_bar = hidden_library_builder.search_bar

    def details_builder = @details_builder ||= DetailsPage.new
    def details_page = @details_page ||= details_builder.build

    def library_notices = @library_notices ||= LibraryNotices.new

    def bind_library_rows
      if Shared.schema.get_uint("library-rows").positive?
        Shared.schema.bind("library-rows", library, "max-children-per-line", :default)
        Shared.schema.bind("library-rows", hidden_library, "max-children-per-line", :default)
      else
        library.max_children_per_line = 10
        hidden_library.max_children_per_line = 10
      end
    end

    def connect_signals
      search_entry.signal_connect("search-changed") { |*_args| search_changed(false) }
      hidden_search_entry.signal_connect("search-changed") { |*_args| search_changed(true) }
      search_entry.signal_connect("activate") { |*_args| show_details_page_search(false) }
      hidden_search_entry.signal_connect("activate") { |*_args| show_details_page_search(true) }

      Adwaita::StyleManager.default.signal_connect("notify::dark") { |*_args| set_details_view_opacity }
      Adwaita::StyleManager.default.signal_connect("notify::high-contrast") { |*_args| set_details_view_opacity }

      setup_actions
    end

    # --- Sidebar logic, ported from CartridgesWindow.create_source_rows --

    def create_source_rows
      source_games = Shared.store&.source_games || {}

      source_rows.each_value { |row| sidebar.remove(row.parent) }
      source_rows.clear

      total = 0
      selected_source = selected_filter_state

      if (removed_total = removable_games(source_games["imported"] || {})) && (count = source_games.fetch("imported", {}).size - removed_total) > 0
        added_row.count_label.label = count.to_s
        added_row.parent.visible = true
        total += count
      else
        added_row.parent.visible = false
      end

      source_games.each do |source_id, games|
        next if source_id == "imported"

        removed = removable_games(games)
        count = games.size - removed
        next unless count.positive?

        total += count

        row = SourceRow.new(source_id, Window.source_name(source_id), count)
        sidebar.insert(row, insertion_index(count))
        source_rows[source_id] = row
      end

      all_games_row.count_label.label = total.to_s
      restore_selection(selected_source)
    end

    def self.source_name(source_id)
      return "All Games" if source_id == "all"
      return "Added" if source_id == "imported"

      split_id = source_id.to_s.split("_").first
      split_id == "desktop" ? "Desktop Entries" : split_id.capitalize
    end

    # --- Filtering, sorting and the empty-state notices -------------------

    def filter_func(child)
      # A FlowBoxChild's content can be briefly nil while DisplayManager
      # moves its GameTile between the shown and hidden library.
      return false unless child.child

      game = child.child.model
      text = (showing_hidden? ? hidden_search_entry : search_entry).text.downcase

      filtered = !text.empty? && !(game.name.downcase.include?(text) || (game.developer && game.developer.downcase.include?(text)))
      filtered ||= filter_state != "all" && game.base_source != filter_state unless filtered

      game.filtered = filtered
      set_library_child
      !filtered
    end

    def sort_func(child1, child2)
      game1, game2 = child1.child.model, child2.child.model
      var, newest_first = sort_variable

      value1, value2 = [game1, game2].map { |g| normalized_sort_value(g, var) }

      if var != "name" && value1 == value2
        var, newest_first = "name", false
        value1, value2 = [game1, game2].map { |g| normalized_sort_value(g, var) }
      end

      ((value1 > value2) ^ newest_first) ? 1 : -1
    end

    def sort_variable
      case sort_state
      when "newest" then ["added", true]
      when "oldest" then ["added", false]
      when "last_played" then ["last_played", true]
      when "z-a" then ["name", true]
      else ["name", false]
      end
    end

    def normalized_sort_value(game, var)
      game.public_send(var).to_s.downcase.sub(/^the /, "")
    end

    def set_library_child
      games = Shared.store || []
      shown_child = empty_notice_for(games, hidden: false)
      hidden_child = empty_notice_for(games, hidden: true)

      swap_overlay_child(library_overlay, shown_child)
      swap_overlay_child(hidden_library_builder.overlay, hidden_child)
    end

    def empty_notice_for(games, hidden:)
      relevant = games.reject { |g| g.removed? || g.blacklisted? }.select { |g| g.hidden? == hidden }
      if relevant.empty?
        hidden ? library_notices.hidden_empty : library_notices.empty
      elsif relevant.all?(&:filtered?)
        hidden ? library_notices.hidden_no_results : library_notices.no_results
      end
    end

    def swap_overlay_child(overlay, child)
      [library_notices.empty, library_notices.no_results, library_notices.hidden_empty, library_notices.hidden_no_results].each do |notice|
        overlay.remove_overlay(notice) if notice.parent == overlay
      end
      overlay.add_overlay(child) if child
    end

    # --- Details page -------------------------------------------------

    def set_active_game(game) = @active_game = game

    def show_details_page(game)
      @active_game = game

      details_builder.cover.opacity = game.loading? ? 0 : 1
      details_builder.spinner.visible = game.loading?
      details_builder.developer.label = game.developer || ""
      details_builder.developer.visible = !(game.developer || "").empty?
      details_builder.hide_button.icon_name = game.hidden? ? "view-reveal-symbolic" : "view-conceal-symbolic"
      details_builder.hide_button.tooltip_text = game.hidden? ? "Unhide" : "Hide"

      @details_view_game_cover&.pictures&.delete(details_builder.cover)
      @details_view_game_cover = game_covers[game.game_id]
      @details_view_game_cover&.add_picture(details_builder.cover)
      details_builder.blurred_cover.paintable = @details_view_game_cover&.get_blurred

      details_builder.title.label = game.name
      details_page.title = game.name

      details_builder.added_label.label = "Added: #{RelativeDate.format(game.added)}"
      details_builder.last_played_label.label = "Last played: #{game.last_played.to_i.positive? ? RelativeDate.format(game.last_played) : 'Never'}"

      if navigation_view.visible_page != details_page
        navigation_view.push(details_page)
        window.set_focus(details_builder.play_button)
      end

      set_details_view_opacity
    end

    def set_details_view_opacity
      return unless navigation_view.visible_page == details_page
      return unless @details_view_game_cover

      style_manager = Adwaita::StyleManager.default
      if style_manager.high_contrast? || !style_manager.system_supports_color_schemes?
        details_builder.blurred_cover.opacity = 0.3
      else
        luminance = @details_view_game_cover.luminance || GameCover::PLACEHOLDER_LUMINANCE
        details_builder.blurred_cover.opacity = style_manager.dark? ? (1 - luminance[0]) : luminance[1]
      end
    end

    # --- Window actions, ported from the `on_*_action` methods -----------

    def setup_actions
      {
        "show_sidebar" => method(:on_show_sidebar_action),
        "show_hidden" => method(:on_show_hidden_action),
        "go_to_parent" => method(:on_go_to_parent_action),
        "go_home" => method(:on_go_home_action),
        "toggle_search" => method(:on_toggle_search_action),
        "undo" => method(:on_undo_action_no_args),
        "open_menu" => method(:on_open_menu_action),
        "close" => method(:on_close_action),
      }.each do |name, callback|
        Gio::SimpleAction.new(name, nil).tap do |action|
          action.signal_connect("activate") { |*_args| callback.call }
          window.add_action(action)
        end
      end

      Gio::SimpleAction.new("sort_by", GLib::VariantType.new("s"), GLib::Variant.new(Shared.state_schema.get_string("sort-mode"))).tap do |action|
        action.signal_connect("activate") { |_action, state| on_sort_action(action, state) }
        window.add_action(action)
        on_sort_action(action, GLib::Variant.new(Shared.state_schema.get_string("sort-mode")))
      end

      set_show_hidden
    end

    def set_show_hidden
      window.lookup_action("show_hidden").enabled = navigation_view.visible_page == library_page
    end

    def on_show_sidebar_action
      Shared.state_schema.set_boolean("show-sidebar", !overlay_split_view.show_sidebar?)
      overlay_split_view.show_sidebar = !overlay_split_view.show_sidebar?
    end

    def on_show_hidden_action
      navigation_view.push(hidden_library_page) unless navigation_view.visible_page == hidden_library_page
    end

    def on_go_to_parent_action
      navigation_view.pop if navigation_view.visible_page == details_page
    end

    def on_go_home_action = navigation_view.pop_to_page(library_page)

    def on_sort_action(action, state)
      # The "activate" signal on a parameterised action hands this binding
      # the already-unwrapped Ruby value, not the GLib::Variant it takes —
      # wrap it back before handing it to SimpleAction#state=.
      variant = state.is_a?(GLib::Variant) ? state : GLib::Variant.new(state.to_s)
      action.state = variant
      @sort_state = variant.to_s.delete("'")
      library.invalidate_sort
      Shared.state_schema.set_string("sort-mode", @sort_state)
    end

    def on_toggle_search_action
      bar, entry = showing_hidden? ? [hidden_search_bar, hidden_search_entry] : [search_bar, search_entry]
      return unless [library_page, hidden_library_page].include?(navigation_view.visible_page)

      mode = !bar.search_mode?
      bar.search_mode = mode
      window.set_focus(entry) if mode
      entry.text = ""
    end

    def show_details_page_search(hidden)
      flow = hidden ? hidden_library : library
      index = 0
      while (child = flow.get_child_at_index(index))
        if filter_func(child)
          show_details_page(child.child.model)
          break
        end
        index += 1
      end
    end

    def on_undo_action_no_args
      return if toasts.empty?

      game, undo = toasts.keys.last
      apply_undo(game, undo)
    end

    def on_undo_action(game, undo)
      apply_undo(game, undo)
    end

    def on_open_menu_action
      primary_menu_button.popup if navigation_view.visible_page == library_page
      hidden_library_builder.menu_button.popup if navigation_view.visible_page == hidden_library_page
    end

    def on_close_action = window.close

    private

      def apply_undo(game, undo)
        tile = game_tiles[game.game_id]
        if undo == "hide"
          tile&.toggle_hidden(toast: false)
        elsif undo == "remove"
          game.removed = false
          game.save
          game.update
        end
        toasts.delete([game, undo])&.dismiss
      end

      def search_changed(hidden) = (hidden ? hidden_library : library).invalidate_filter

      def showing_hidden? = navigation_view.visible_page == hidden_library_page

      def row_selected(row)
        return unless row

        @filter_state =
          if row == all_games_row.parent
            "all"
          elsif row == added_row.parent
            "imported"
          else
            source_rows.find { |_id, source_row| source_row.parent == row }&.first || "all"
          end

        library_page.title = Window.source_name(@filter_state)
        library.invalidate_filter
        overlay_split_view.show_sidebar = false if overlay_split_view.collapsed?
      end

      def selected_filter_state = @filter_state

      def restore_selection(previous)
        if source_rows.key?(previous)
          sidebar.select_row(source_rows[previous].parent)
        elsif previous == "imported" && added_row.parent.visible?
          sidebar.select_row(added_row.parent)
        else
          sidebar.select_row(all_games_row.parent)
        end
      end

      def removable_games(games)
        games.values.count { |game| game.removed? || game.hidden? || game.blacklisted? }
      end

      def insertion_index(games_no)
        index = 3
        index += 1 while (row = sidebar.get_row_at_index(index)) && source_rows.find { |_id, sr| sr.parent == row }&.last&.games_no.to_i >= games_no
        index
      end
  end
end
