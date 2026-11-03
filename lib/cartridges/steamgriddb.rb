# frozen_string_literal: true

require "pathname"
require "tmpdir"
require_relative "shared"
require_relative "http_client"
require_relative "save_cover"
require_relative "logging/setup"

module Cartridges
  # SgdbError and its subclasses are the failures a SteamGridDB lookup can
  # hit. SgdbAuthError is the one the manager turns into the user-facing
  # "Couldn't Authenticate SteamGridDB" error.
  #
  # Ported from cartridges/utils/steamgriddb.py.
  class SgdbError < StandardError; end
  class SgdbAuthError < SgdbError; end
  class SgdbGameNotFound < SgdbError; end
  class SgdbBadRequest < SgdbError; end
  class SgdbNoImageFound < SgdbError; end

  # SgdbHelper queries SteamGridDB for a game's cover: first the game id that
  # matches the name, then a 600x900 grid for that id, animated first when the
  # user asked for animated covers.
  #
  # Ported from the SgdbHelper class in cartridges/utils/steamgriddb.py.
  class SgdbHelper
    BASE_URL = "https://www.steamgriddb.com/api/v2/"

    def auth_headers
      { "Authorization" => "Bearer #{Shared.schema.get_string("sgdb-key")}" }
    end

    # The SteamGridDB id for a game, matched on its name.
    def game_id(game)
      get("#{BASE_URL}search/autocomplete/#{escape(game.name)}").then do |response|
        case response.code
        when 200 then response.json.dig("data", 0, "id")
        when 401 then raise SgdbAuthError, error_message(response)
        when 404 then raise SgdbGameNotFound, response.code.to_s
        else response.raise_for_status!
        end
      end
    end

    # The URL of a grid image for a SteamGridDB game id.
    def image_uri(sgdb_id, animated: false)
      get(grid_uri(sgdb_id, animated)).then do |response|
        case response.code
        when 200 then first_image(response)
        when 401 then raise SgdbAuthError, error_message(response)
        when 404 then raise SgdbGameNotFound, response.code.to_s
        else response.raise_for_status!
        end
      end
    end

    # Replaces the game's cover when the settings say SteamGridDB should win,
    # or when there is no cover yet.
    def conditionally_update_cover(game)
      if update_wanted?(game)
        game_id(game).then do |sgdb_id|
          download_first(game, sgdb_id)
        end
      end
    end

    private

      def update_wanted?(game)
        Shared.schema.get_boolean("sgdb") && !game.blacklisted? && !already_covered?(game)
      end

      # An existing cover stays unless the user asked to prefer SteamGridDB.
      def already_covered?(game)
        !Shared.schema.get_boolean("sgdb-prefer") &&
          [Shared::COVERS_DIR / "#{game.game_id}.tiff", Shared::COVERS_DIR / "#{game.game_id}.gif"]
          .any? { |path| path.file? }
      end

      # Animated is tried first when the user wants animated covers, and a
      # still image is always the fallback.
      def uri_options
        if Shared.schema.get_boolean("sgdb-animated")
          [true, false]
        else
          [false]
        end
      end

      def download_first(game, sgdb_id)
        uri_options.any? { |animated| try_download(game, sgdb_id, animated) }.then do |done|
          unless done
            no_image(game, sgdb_id)
          end
        end
      end

      # One attempt at one of the image variants. An auth error is the caller's
      # problem; anything else just moves on to the next variant.
      def try_download(game, sgdb_id, animated)
        download(game, sgdb_id, animated)
        true
      rescue SgdbAuthError
        raise
      rescue HttpError, SgdbError => e
        Logging.logger.warn("#{e.class.name} while getting image for #{game.name} (animated=#{animated})")
        false
      end

      def download(game, sgdb_id, animated)
        image_uri(sgdb_id, animated: animated).then do |uri|
          temp_file(uri).then do |path|
            SaveCover.save_cover(game.game_id, SaveCover.convert_cover(path))
          end
        end
      end

      def no_image(game, sgdb_id)
        Logging.logger.warn("No matching image found for game \"#{game.name}\" (SGDB ID #{sgdb_id})")
        raise SgdbNoImageFound
      end

      def temp_file(uri)
        HttpClient.get(uri).raise_for_status!.then do |response|
          (Pathname.new(Dir.mktmpdir("cartridges-sgdb")) / "cover").tap do |path|
            path.binwrite(response.body)
          end
        end
      end

      def grid_uri(sgdb_id, animated)
        "#{BASE_URL}grids/game/#{sgdb_id}?dimensions=600x900".then do |uri|
          animated ? "#{uri}&types=animated" : uri
        end
      end

      def first_image(response)
        response.json["data"].then do |data|
          if Array(data).empty?
            raise SgdbNoImageFound
          end

          data[0]["url"]
        end
      end

      def error_message(response)
        Array(response.json["errors"]).first.to_s
      rescue JSON::ParserError
        response.body.to_s
      end

      def get(uri) = HttpClient.get(uri, headers: auth_headers)

      def escape(name) = URI.encode_www_form_component(name.to_s)
  end
end
