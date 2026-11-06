# frozen_string_literal: true

require_relative "manager"
require_relative "steam_api_manager"
require_relative "sgdb_manager"
require_relative "../../shared"
require_relative "../../game"
require_relative "../../game_cover"

module Cartridges
  class Store
    # DisplayManager is in charge of putting a game's tile in the window: it
    # builds the GameTile the first time a game is seen, keeps it in the
    # library or hidden library flow box that matches the model's current
    # "hidden" flag, shares one GameCover per game id across every window
    # that shows it, and refreshes the details page when it is the one open.
    #
    # Ported from cartridges/store/managers/display_manager.py.
    class DisplayManager < Manager
      self.run_after = [SteamAPIManager, SgdbManager]
      self.signals = ["update-ready"]

      def main(game, _additional_data)
        win = Shared.win
        return unless win

        tile = win.game_tiles[game.game_id] ||= GameTile.new(game)
        attach_cover(win, tile, game)
        unparent(tile)

        unless game.removed? || game.blacklisted?
          (game.hidden? ? win.hidden_library : win.library).append(tile)
          tile.parent&.focusable = false
        end

        refresh_details_page(win, game)

        win.set_library_child

        win.create_source_rows if Shared.app_state == AppState::DEFAULT
      end

      private

        def attach_cover(win, tile, game)
          cover = win.game_covers[game.game_id] ||= GameCover.new([])
          tile.attach_cover(cover) unless tile.game_cover
        end

        # Removing a FlowBoxChild from its FlowBox does not itself clear the
        # child widget's parent pointer (it is still the FlowBoxChild's
        # child); without clearing it explicitly, re-appending the tile to a
        # flow box (this one or the other) fails a GTK assertion.
        def unparent(tile)
          tile.parent.then do |flow_box_child|
            next unless flow_box_child

            box = flow_box_child.parent
            flow_box_child.child = nil
            box&.remove(flow_box_child)
          end
        end

        def refresh_details_page(win, game)
          return unless win.navigation_view.visible_page == win.details_page
          return unless win.active_game.equal?(game)

          win.show_details_page(game)
        end
    end
  end
end
