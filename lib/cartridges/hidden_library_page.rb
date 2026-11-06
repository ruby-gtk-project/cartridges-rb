# frozen_string_literal: true

require "adwaita"
require_relative "library_notices"
require_relative "window_menus"

module Cartridges
  # HiddenLibraryPage is the navigation page for hidden games: its own header
  # bar, search bar and flow box, laid out exactly like the main library but
  # pushed onto the navigation view rather than shown in the split view.
  #
  # Ported from the standalone `hidden_library_page` Adw.NavigationPage at the
  # root of data/gtk/window.blp.
  class HiddenLibraryPage
    attr_reader :notices

    def initialize
      @notices = LibraryNotices.new
    end

    def build
      page.tap do |p|
        p.child = toolbar_view
        search_bar.key_capture_widget = toolbar_view
      end
    end

    def page = @page ||= Adwaita::NavigationPage.new(toolbar_view, "Hidden Games")

    def toolbar_view
      @toolbar_view ||= Adwaita::ToolbarView.new.tap do |view|
        view.add_top_bar(header_bar)
        view.add_top_bar(search_bar)
        view.content = overlay
        view.add_css_class("background")
      end
    end

    def header_bar
      @header_bar ||= Adwaita::HeaderBar.new.tap do |hb|
        hb.pack_end(menu_button)
        hb.pack_end(search_button)
      end
    end

    def menu_button
      @menu_button ||= Gtk::MenuButton.new.tap do |btn|
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
      end
    end

    def search_entry
      @search_entry ||= Gtk::SearchEntry.new.tap do |entry|
        entry.placeholder_text = "Search"
        entry.hexpand = true
      end
    end

    def overlay
      @overlay ||= Gtk::Overlay.new.tap { |o| o.child = scrolled_window }
    end

    def scrolled_window
      @scrolled_window ||= Gtk::ScrolledWindow.new.tap { |sw| sw.child = library }
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
  end
end
