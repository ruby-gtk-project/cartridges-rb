# frozen_string_literal: true

require "gtk4"

module Cartridges
  # GameMenus builds the two popover menus a library tile can show: the one
  # for a visible game and the one for a hidden game, which differ only in
  # whether the middle item says "Hide" or "Unhide".
  #
  # Ported from the `game_options` and `hidden_game_options` menu models at
  # the bottom of data/gtk/game.blp.
  module GameMenus
    class << self
      def game_options
        @game_options ||= Gio::Menu.new.tap do |menu|
          menu.append_section(
            nil,
            Gio::Menu.new.tap do |section|
              section.append("Edit", "app.edit_game")
              section.append("Hide", "app.hide_game")
              section.append("Remove", "app.remove_game")
            end,
          )
        end
      end

      def hidden_game_options
        @hidden_game_options ||= Gio::Menu.new.tap do |menu|
          menu.append_section(
            nil,
            Gio::Menu.new.tap do |section|
              section.append("Edit", "app.edit_game")
              section.append("Unhide", "app.hide_game")
              section.append("Remove", "app.remove_game")
            end,
          )
        end
      end
    end
  end
end
