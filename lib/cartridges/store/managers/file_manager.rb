# frozen_string_literal: true

require "fileutils"
require "json"
require_relative "async_manager"
require_relative "steam_api_manager"
require_relative "../../shared"

module Cartridges
  class Store
    # FileManager writes a game out as <game_id>.json in the games directory.
    # Games being loaded from disk carry skip_save, so a start-up scan does
    # not rewrite every file it just read.
    #
    # Ported from cartridges/store/managers/file_manager.py.
    class FileManager < AsyncManager
      self.run_after = [SteamAPIManager]
      self.signals = ["save-ready"]

      def main(game, additional_data)
        unless additional_data["skip_save"] || additional_data[:skip_save]
          write(game)
        end
      end

      private

        def write(game)
          FileUtils.mkdir_p(Shared::GAMES_DIR)
          (Shared::GAMES_DIR / "#{game.game_id}.json").then do |path|
            File.write(path, "#{JSON.pretty_generate(game.to_h)}\n")
          end
        end
    end
  end
end
