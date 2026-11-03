# frozen_string_literal: true

require_relative "async_manager"
require_relative "../../steam"
require_relative "../../http_client"

module Cartridges
  class Store
    # SteamAPIManager fills in the metadata the local Steam manifests do not
    # carry — the developer — and blacklists anything the storefront says is
    # not a game.
    #
    # Ported from cartridges/store/managers/steam_api_manager.py.
    class SteamAPIManager < AsyncManager
      self.retryable_on = HttpClient::RETRYABLE

      attr_reader :steam_api_helper, :steam_rate_limiter

      def initialize
        super
        @steam_rate_limiter = SteamRateLimiter.new
        @steam_api_helper = SteamAPIHelper.new(@steam_rate_limiter)
      end

      def main(game, additional_data)
        (additional_data["steam_appid"] || additional_data[:steam_appid]).then do |appid|
          if appid
            apply(game, appid)
          end
        end
      end

      private

        def apply(game, appid)
          game.update_values(@steam_api_helper.api_data(appid))
        rescue SteamNotAGameError, SteamGameNotFoundError
          game.update_values({ "blacklisted" => true })
        end
    end
  end
end
