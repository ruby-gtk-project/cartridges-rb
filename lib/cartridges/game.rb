# frozen_string_literal: true

require "adwaita"
require_relative "shared"
require_relative "game_menus"
require_relative "game_cover"

module Cartridges
  # GameTile is a library tile: the cover, the play/menu buttons that fade in
  # on hover, and the title underneath. It wraps a GameModel but owns none of
  # the game's data itself, redrawing from the model on "update-ready".
  #
  # Ported from the widget half of cartridges/game.py and data/gtk/game.blp.
  # The record half of game.py is lib/cartridges/game_model.rb; the signal
  # wiring that moves a tile between the shown and hidden library and keeps
  # the window's bookkeeping in sync is lib/cartridges/store/managers/display_manager.rb.
  class GameTile < Gtk::Box
    attr_reader :model, :game_cover

    def initialize(model)
      super(:vertical, 0)
      @model = model
      @game_cover = nil

      self.halign = :center
      self.valign = :start

      build
      refresh
      set_play_icon

      Shared.schema.signal_connect("changed") { |_settings, key| set_play_icon if key == "cover-launches-game" }
      model.signal_connect("update-ready") { |*_args| refresh }
    end

    # Points this tile's cover at the shared GameCover for the model's
    # game_id, creating one the first time a tile is built for it.
    def attach_cover(game_cover)
      @game_cover = game_cover
      @game_cover.add_picture(cover)
    end

    def build
      append(clamp)
    end

    def refresh
      title.label = model.name
      menu_button.menu_model = model.hidden? ? GameMenus.hidden_game_options : GameMenus.game_options
      cover.opacity = model.loading? ? 0 : 1
      spinner.visible = model.loading?
    end

    # Hover and menu-popover handling: the play/menu buttons reveal on
    # pointer hover and hide again once the pointer leaves or the popover
    # that was open closes, guarded so an open popover is never hidden out
    # from under a click.
    def reveal(show)
      unless menu_button.active?
        play_revealer.reveal_child = show
        menu_revealer.reveal_child = show
      end
    end

    def main_button_clicked(play)
      if Shared.schema.get_boolean("cover-launches-game") ^ play
        launch
      else
        Shared.win.show_details_page(model)
      end
    end

    def launch
      Shared.win.application.quit if model.launch
      create_toast("#{model.name} launched")
    end

    def toggle_hidden(toast: true)
      hidden = model.toggle_hidden
      Shared.win.navigation_view.pop if Shared.win.navigation_view.visible_page == Shared.win.details_page
      create_toast(hidden ? "#{model.name} hidden" : "#{model.name} unhidden", action: "hide") if toast
    end

    def remove_game
      model.remove_game
      Shared.win.navigation_view.pop if Shared.win.navigation_view.visible_page == Shared.win.details_page
      create_toast("#{model.name} removed", action: "remove")
    end

    def create_toast(title, action: nil)
      Adwaita::Toast.new(title).tap do |toast|
        toast.priority = :high
        toast.use_markup = false

        if action
          toast.button_label = "Undo"
          toast.signal_connect("button-clicked") { Shared.win.on_undo_action(model, action) }
          Shared.win.toasts[[model, action]]&.dismiss
          Shared.win.toasts[[model, action]] = toast
        end

        Shared.win.toast_overlay.add_toast(toast)
      end
    end

    def set_play_icon
      play_button.icon_name = Shared.schema.get_boolean("cover-launches-game") ? "help-about-symbolic" : "media-playback-start-symbolic"
    end

    # Memoized widget methods

    def clamp
      @clamp ||= Adwaita::Clamp.new.tap do |c|
        c.maximum_size = 200
        c.child = overlay
      end
    end

    def overlay
      @overlay ||= Gtk::Overlay.new.tap do |o|
        o.add_overlay(play_revealer)
        o.add_overlay(menu_revealer)
        o.child = cover_button

        motion_controller.tap do |controller|
          o.add_controller(controller)
          controller.signal_connect("enter") { |*_args| reveal(true) }
          controller.signal_connect("leave") { |*_args| reveal(false) }
        end
      end
    end

    def motion_controller = @motion_controller ||= Gtk::EventControllerMotion.new

    def play_revealer
      @play_revealer ||= Gtk::Revealer.new.tap do |r|
        r.transition_type = :crossfade
        r.valign = :start
        r.halign = :start
        r.child = play_button
      end
    end

    def play_button
      @play_button ||= Gtk::Button.new.tap do |btn|
        btn.margin_start = 6
        btn.margin_end = 3
        btn.margin_top = 6
        btn.margin_bottom = 3
        btn.add_css_class("circular")
        btn.add_css_class("osd")
        btn.signal_connect("clicked") { main_button_clicked(true) }
      end
    end

    def menu_revealer
      @menu_revealer ||= Gtk::Revealer.new.tap do |r|
        r.transition_type = :crossfade
        r.valign = :start
        r.halign = :end
        r.child = menu_button
      end
    end

    def menu_button
      @menu_button ||= Gtk::MenuButton.new.tap do |btn|
        btn.icon_name = "view-more-symbolic"
        btn.margin_start = 3
        btn.margin_end = 6
        btn.margin_top = 6
        btn.margin_bottom = 3
        btn.add_css_class("circular")
        btn.add_css_class("osd")
        # A MenuButton has no popover until a menu model gives it one; the
        # real model is set per-game in #refresh.
        btn.menu_model = GameMenus.game_options

        btn.popover.signal_connect("notify::visible") do
          reveal(false)
          Shared.win.set_active_game(model)
        end
      end
    end

    def cover_button
      @cover_button ||= Gtk::Button.new.tap do |btn|
        btn.overflow = :hidden
        btn.add_css_class("card")
        btn.child = cover_box
        btn.signal_connect("clicked") { main_button_clicked(false) }
      end
    end

    def cover_box
      @cover_box ||= Gtk::Box.new(:vertical, 0).tap do |box|
        box.append(cover_overlay)
        box.append(title)
      end
    end

    def cover_overlay
      @cover_overlay ||= Gtk::Overlay.new.tap do |o|
        o.add_overlay(spinner)
        o.child = cover
      end
    end

    def spinner
      @spinner ||= Adwaita::Spinner.new.tap do |s|
        s.visible = false
      end
    end

    def cover
      @cover ||= Gtk::Picture.new.tap do |p|
        p.width_request = 200
        p.height_request = 300
        p.hexpand = true
        p.vexpand = true
      end
    end

    def title
      @title ||= Gtk::Label.new.tap do |label|
        label.ellipsize = :end
        label.hexpand = true
        label.halign = :start
        label.margin_top = 15
        label.margin_bottom = 15
        label.margin_start = 12
        label.margin_end = 12
      end
    end
  end
end
