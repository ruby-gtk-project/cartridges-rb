# frozen_string_literal: true

require "json"
require_relative "shared"
require_relative "http_client"
require_relative "rate_limiter"
require_relative "logging/setup"

module Cartridges
  # SteamError and its subclasses are the failures the Steam import can hit.
  #
  # Ported from cartridges/utils/steam.py.
  class SteamError < StandardError; end
  class SteamGameNotFoundError < SteamError; end
  class SteamNotAGameError < SteamError; end
  class SteamInvalidManifestError < SteamError; end

  # SteamRateLimiter is the token bucket for the Steam web API: 200 requests
  # per five minutes, 100 of which may be spent at once. The pick history is
  # kept in the .State schema so the limit survives a restart.
  #
  # Ported from the SteamRateLimiter class in cartridges/utils/steam.py.
  class SteamRateLimiter < RateLimiter
    self.refill_period_seconds = 5 * 60
    self.refill_period_tokens = 200
    self.burst_tokens = 100

    HISTORY_KEY = "steam-limiter-tokens-history"

    # Takes a token, then writes the pick history back to the schema.
    def acquire
      super
      Shared.state_schema.set_string(HISTORY_KEY, JSON.generate(pick_history.copy_timestamps))
    end

    private

      # Seeds the history from the schema, so API limits are remembered
      # through restarts of Cartridges.
      def init_pick_history
        super
        pick_history.add(*stored_timestamps)
        pick_history.remove_old_entries
      end

      def stored_timestamps
        JSON.parse(Shared.state_schema.get_string(HISTORY_KEY))
      rescue JSON::ParserError
        []
      end
  end

  # SteamFileHelper reads Steam's own file formats. The only one the importer
  # needs is the app manifest (appmanifest_<appid>.acf), whose three
  # interesting keys are pulled out with the same regex upstream uses rather
  # than by parsing VDF in full.
  #
  # Ported from the SteamFileHelper class in cartridges/utils/steam.py.
  class SteamFileHelper
    # The keys SteamManifestData declares as required upstream.
    MANIFEST_KEYS = %w[name appid stateflags].freeze

    # The local data for a game, read out of its manifest.
    def manifest_data(manifest_path)
      File.read(manifest_path, encoding: "UTF-8").then do |contents|
        MANIFEST_KEYS.to_h { |key| [key, match_key(contents, key)] }
      end
    end

    private

      def match_key(contents, key)
        contents.match(/"#{key}"\s+"(.*)"\n/i).then do |match|
          unless match
            raise SteamInvalidManifestError, "no #{key} in manifest"
          end

          match[1]
        end
      end
  end

  # SteamAPIHelper asks the Steam storefront API for the metadata the local
  # manifests do not carry — which, for this app, is the developer list.
  #
  # Ported from the SteamAPIHelper class in cartridges/utils/steam.py.
  # See https://wiki.teamfortress.com/wiki/User:RJackson/StorefrontAPI#appdetails
  class SteamAPIHelper
    BASE_URL = "https://store.steampowered.com/api"

    # The app types that count as a game.
    GAME_TYPES = %w[game demo mod].freeze

    def initialize(rate_limiter) = @rate_limiter = rate_limiter

    # Blocks as long as the rate limiter says it must, then returns the
    # metadata fields the app keeps.
    def api_data(appid)
      app_details(appid).then do |data|
        unless data["success"]
          Logging.logger.debug("Appid #{appid} not found")
          raise SteamGameNotFoundError
        end

        unless GAME_TYPES.include?(data.dig("data", "type"))
          Logging.logger.debug("Appid #{appid} is not a game")
          raise SteamNotAGameError
        end

        { "developer" => Array(data.dig("data", "developers")).join(", ") }
      end
    end

    private

      def app_details(appid)
        @rate_limiter.with_token do
          HttpClient.get("#{BASE_URL}/appdetails?appids=#{appid}")
                    .raise_for_status!
                    .json
                    .fetch(appid.to_s)
        end
      rescue HttpError => e
        Logging.logger.warn("Steam API HTTP error for #{appid}: #{e.message}")
        raise e
      end
  end
end
