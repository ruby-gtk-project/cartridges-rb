# frozen_string_literal: true

require_relative "async_manager"
require_relative "cover_manager"
require_relative "steam_api_manager"
require_relative "../../steamgriddb"
require_relative "../../friendly_error"
require_relative "../../http_client"

module Cartridges
  class Store
    # SgdbManager downloads a game's cover from SteamGridDB. A bad API key
    # cancels every outstanding SteamGridDB task and surfaces as the
    # "Couldn't Authenticate SteamGridDB" error in the import report.
    #
    # Ported from cartridges/store/managers/sgdb_manager.py.
    class SgdbManager < AsyncManager
      self.run_after = [SteamAPIManager, CoverManager]
      self.retryable_on = HttpClient::RETRYABLE + [JSON::ParserError]

      def main(game, _additional_data)
        SgdbHelper.new.conditionally_update_cover(game)
      rescue SgdbAuthError => e
        @cancellable.cancel
        raise FriendlyError.new(
          "Couldn't Authenticate SteamGridDB",
          "Verify your API key in preferences",
          cause: e,
        )
      end
    end
  end
end
