# frozen_string_literal: true

require "fileutils"
require "set"
require_relative "shared"
require_relative "game_model"
require_relative "logging/setup"
require_relative "store/pipeline"
require_relative "store/managers/manager"
require_relative "store/managers/async_manager"
require_relative "store/managers/steam_api_manager"
require_relative "store/managers/cover_manager"
require_relative "store/managers/sgdb_manager"
require_relative "store/managers/file_manager"

module Cartridges
  # Store is what every game added to the app goes through. It holds the
  # managers, keeps one pipeline per game, groups the games by the source they
  # came from, and drops duplicates and already-removed games on the way in.
  #
  # Ported from cartridges/store/store.py. The manager and pipeline classes
  # nest inside this class, matching upstream's cartridges/store/ package.
  class Store
    include Enumerable

    attr_reader :managers, :pipeline_managers, :pipelines, :source_games,
                :new_game_ids, :duplicate_game_ids

    def initialize
      @managers = {}
      @pipeline_managers = Set.new
      @pipelines = {}
      @source_games = {}
      @new_game_ids = Set.new
      @duplicate_game_ids = Set.new
    end

    # Whether a game is in the store, so `store.include?(game)` reads like
    # upstream's `game in store`.
    def include?(game)
      if game.is_a?(GameModel)
        @source_games.fetch(game.base_source, {}).key?(game.game_id)
      else
        false
      end
    end

    # Iterates every game in the store.
    def each(&block)
      @source_games.each_value { |games| games.each_value(&block) }
      self
    end

    def size = @source_games.values.sum(&:size)
    alias length size

    # A game by its id, raising when it is not there.
    def [](game_id)
      find { |game| game.game_id == game_id } ||
        raise(KeyError, "Game not found in store")
    end

    # A game by its id, with a fallback.
    def get(game_id, default = nil)
      find { |game| game.game_id == game_id } || default
    end

    # Adds a manager, and says whether new pipelines should run it.
    def add_manager(manager, in_pipeline: true)
      @managers[manager.class] = manager
      toggle_manager_in_pipelines(manager.class, in_pipeline)
      manager
    end

    # Changes whether a manager runs in new pipelines.
    def toggle_manager_in_pipelines(manager_type, enable)
      if enable
        @pipeline_managers.add(@managers[manager_type])
      else
        @pipeline_managers.delete(@managers[manager_type])
      end
    end

    # Removes a game's files and dismisses any undo toast left over for it.
    def cleanup_game(game)
      [
        Shared::GAMES_DIR / "#{game.game_id}.json",
        Shared::COVERS_DIR / "#{game.game_id}.tiff",
        Shared::COVERS_DIR / "#{game.game_id}.gif",
      ].each { |path| FileUtils.rm_f(path.to_s) }

      dismiss_toasts(game)
    end

    # Adds a game to the app, returning the pipeline it is going through, or
    # nil when the game was ignored.
    def add_game(game, additional_data, run_pipeline: true)
      if ignorable?(game)
        nil
      else
        record(game).then do |accepted|
          if accepted
            connect_managers(game)
            store_game(game)
            start_pipeline(game, additional_data, run_pipeline)
          end
        end
      end
    end

    private

      # Games from a newer spec version are left alone, and ones already
      # marked removed are just cleaned up.
      def ignorable?(game)
        if game.version.to_f > Shared::SPEC_VERSION
          true
        elsif game.removed?
          cleanup_game(game)
          true
        else
          false
        end
      end

      # Decides what to do about a game id that is already in the store: a
      # removed one is replaced, a live one wins and the newcomer is dropped.
      def record(game)
        get(game.game_id).then do |stored|
          if stored.nil?
            Logging.logger.debug("New store game #{game.name} (#{game.game_id})")
            @new_game_ids.add(game.game_id)
            true
          elsif stored.removed?
            Logging.logger.debug("New store game #{game.name} (#{game.game_id}) (replacing a removed one)")
            cleanup_game(stored)
            @new_game_ids.add(game.game_id)
            true
          else
            Logging.logger.debug("Duplicate store game #{game.name} (#{game.game_id})")
            @duplicate_game_ids.add(game.game_id)
            false
          end
        end
      end

      def connect_managers(game)
        @managers.each_value do |manager|
          manager.signals.each do |signal|
            game.signal_connect(signal) { |_game, data| manager.run(game, data || {}) }
          end
        end
      end

      def store_game(game)
        (@source_games[game.base_source] ||= {}).then do |games|
          games[game.game_id] = game
        end
      end

      def start_pipeline(game, additional_data, run_pipeline)
        if run_pipeline
          Pipeline.new(game, additional_data, @pipeline_managers).tap do |pipeline|
            @pipelines[game.game_id] = pipeline
            pipeline.advance
          end
        end
      end

      def dismiss_toasts(game)
        Shared.win.then do |win|
          if win.respond_to?(:toasts)
            %w[remove hide].each { |undo| win.toasts.delete([game, undo])&.dismiss }
          end
        end
      end
  end
end
