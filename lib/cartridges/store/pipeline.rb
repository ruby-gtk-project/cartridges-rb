# frozen_string_literal: true

require "adwaita"
require "set"
require "monitor"
require_relative "managers/manager"
require_relative "../logging/setup"

module Cartridges
  class Store
    # Pipeline is the set of managers one game still has to go through. It
    # runs whatever is not blocked by an unfinished dependency, and emits
    # "advanced" every time a manager finishes — which is what moves the
    # import dialog's progress bar.
    #
    # Ported from cartridges/store/pipeline.py.
    class Pipeline < GLib::Object
      type_register

      define_signal("advanced", GLib::Signal::RUN_FIRST, nil, nil)

      attr_reader :game, :additional_data, :waiting, :running, :done

      def initialize(game, additional_data, managers)
        super()
        @game = game
        @additional_data = additional_data
        @waiting = Set.new(managers)
        @running = Set.new
        @done = Set.new
        @lock = Monitor.new
      end

      # The managers that have not finished yet.
      def not_done = @waiting | @running

      def done? = @waiting.empty? && @running.empty?

      # The managers that cannot run because something they must follow is
      # still waiting or running.
      def blocked
        not_done.then do |outstanding|
          @waiting.select do |waiting|
            outstanding.any? do |other|
              !waiting.equal?(other) && waiting.run_after.include?(other.class)
            end
          end.to_set
        end
      end

      # The managers that can be run right now.
      def ready = @waiting - blocked

      # A rough idea of how far through the pipeline this game is.
      def progress
        (@waiting.size + @running.size + @done.size).then do |total|
          if total.zero?
            1.0
          else
            @done.size.to_f / total
          end
        end
      end

      # Spawns the managers that are able to run, scheduling the parallel ones
      # before running the blocking ones.
      def advance
        ready.then do |managers|
          managers.select(&:blocking).then do |blocking|
            ((managers - blocking).to_a + blocking.to_a).each { |manager| start(manager) }
          end
        end
      end

      # Called by a manager when it is done.
      def manager_callback(manager)
        Logging.logger.debug("#{manager.name} done for #{@game.game_id}")
        @lock.synchronize do
          @running.delete(manager)
          @done.add(manager)
        end
        signal_emit("advanced")
        advance
      end

      def signal_do_advanced = nil

      private

        def start(manager)
          @lock.synchronize do
            @waiting.delete(manager)
            @running.add(manager)
          end
          manager.process_game(@game, @additional_data, method(:manager_callback))
        end
    end
  end
end
