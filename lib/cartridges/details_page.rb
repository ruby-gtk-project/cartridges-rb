# frozen_string_literal: true

require "adwaita"
require_relative "window_menus"

module Cartridges
  # DetailsPage is the full-page view a library tile opens into: the cover
  # (over a blurred, same-image backdrop), the title, developer, dates, and
  # the play/edit/hide/remove/search toolbar.
  #
  # Ported from the standalone `details_page` Adw.NavigationPage at the root
  # of data/gtk/window.blp.
  class DetailsPage
    def build
      page.tap { |p| p.child = overlay }
    end

    def page = @page ||= Adwaita::NavigationPage.new(overlay, "Game Details")

    def overlay
      @overlay ||= Gtk::Overlay.new.tap do |o|
        o.child = blurred_cover
        o.add_overlay(toolbar_view)
        o.set_measure_overlay(toolbar_view, true)
        o.set_clip_overlay(toolbar_view, false)
      end
    end

    def blurred_cover
      @blurred_cover ||= Gtk::Picture.new.tap { |p| p.keep_aspect_ratio = false }
    end

    def toolbar_view
      @toolbar_view ||= Adwaita::ToolbarView.new.tap do |view|
        view.add_top_bar(Adwaita::HeaderBar.new)
        view.content = scrolled_window
      end
    end

    def scrolled_window
      @scrolled_window ||= Gtk::ScrolledWindow.new.tap { |sw| sw.child = box }
    end

    def box
      @box ||= Gtk::Box.new(:horizontal, 0).tap do |b|
        b.halign = :center
        b.valign = :center
        b.margin_start = 24
        b.margin_end = 24
        b.margin_top = 24
        b.margin_bottom = 24
        b.append(cover_clamp)
        b.append(details_box)
      end
    end

    def cover_clamp
      @cover_clamp ||= Adwaita::Clamp.new.tap do |c|
        c.maximum_size = 200
        c.child = cover_overlay
      end
    end

    def cover_overlay
      @cover_overlay ||= Gtk::Overlay.new.tap do |o|
        o.add_overlay(spinner)
        o.child = cover
      end
    end

    def spinner
      @spinner ||= Adwaita::Spinner.new.tap { |s| s.visible = false }
    end

    def cover
      @cover ||= Gtk::Picture.new.tap do |p|
        p.halign = :end
        p.valign = :start
        p.width_request = 200
        p.height_request = 300
        p.add_css_class("card")
      end
    end

    def details_box
      @details_box ||= Gtk::Box.new(:vertical, 0).tap do |b|
        b.margin_start = 48
        b.vexpand = true
        b.valign = :center
        b.append(title)
        b.append(developer)
        b.append(date_box)
        b.append(toolbar_box)
      end
    end

    def title
      @title ||= Gtk::Label.new.tap do |label|
        label.hexpand = true
        label.halign = :start
        label.max_width_chars = 24
        label.wrap = true
        label.wrap_mode = :word_char
        label.add_css_class("title-1")
      end
    end

    def developer
      @developer ||= Gtk::Label.new.tap do |label|
        label.margin_top = 6
        label.hexpand = true
        label.halign = :start
        label.max_width_chars = 36
        label.wrap = true
        label.wrap_mode = :word_char
        label.add_css_class("heading")
      end
    end

    def date_box
      @date_box ||= Gtk::Box.new(:horizontal, 0).tap do |b|
        b.margin_top = 15
        b.hexpand = true
        b.halign = :start
        b.append(added_label)
        b.append(last_played_label)
      end
    end

    def added_label
      @added_label ||= Gtk::Label.new.tap do |label|
        label.wrap = true
        label.wrap_mode = :word_char
        label.justify = :center
      end
    end

    def last_played_label
      @last_played_label ||= Gtk::Label.new.tap do |label|
        label.margin_start = 12
        label.wrap = true
        label.wrap_mode = :word_char
        label.justify = :center
      end
    end

    def toolbar_box
      @toolbar_box ||= Gtk::Box.new(:horizontal, 0).tap do |b|
        b.hexpand = true
        b.vexpand = true
        b.valign = :center
        b.append(play_button)
        b.append(toolbar_buttons)
      end
    end

    def play_button
      @play_button ||= Gtk::Button.new.tap do |btn|
        btn.action_name = "app.launch_game"
        btn.label = "Play"
        btn.halign = :start
        btn.margin_top = 24
        btn.add_css_class("opaque")
        btn.add_css_class("pill")
      end
    end

    def toolbar_buttons
      @toolbar_buttons ||= Gtk::Box.new(:horizontal, 0).tap do |b|
        b.halign = :start
        b.valign = :center
        b.margin_top = 24
        b.margin_start = 9
        b.add_css_class("toolbar")
        b.append(edit_button)
        b.append(hide_button)
        b.append(remove_button)
        b.append(search_menu_button)
      end
    end

    def edit_button
      @edit_button ||= Gtk::Button.new.tap do |btn|
        btn.icon_name = "document-edit-symbolic"
        btn.action_name = "app.edit_game"
        btn.tooltip_text = "Edit"
        btn.add_css_class("raised")
        btn.add_css_class("circular")
      end
    end

    def hide_button
      @hide_button ||= Gtk::Button.new.tap do |btn|
        btn.action_name = "app.hide_game"
        btn.add_css_class("raised")
        btn.add_css_class("circular")
      end
    end

    def remove_button
      @remove_button ||= Gtk::Button.new.tap do |btn|
        btn.icon_name = "user-trash-symbolic"
        btn.action_name = "app.remove_game"
        btn.tooltip_text = "Remove"
        btn.add_css_class("raised")
        btn.add_css_class("circular")
      end
    end

    def search_menu_button
      @search_menu_button ||= Gtk::MenuButton.new.tap do |btn|
        btn.icon_name = "system-search-symbolic"
        btn.menu_model = WindowMenus.search
        btn.tooltip_text = "Search"
        btn.add_css_class("raised")
        btn.add_css_class("circular")
      end
    end
  end
end
