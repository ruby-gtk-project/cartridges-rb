# frozen_string_literal: true

require "adwaita"
require_relative "manager"

module Cartridges
  class Store
    # AsyncManager is a Manager that runs on its own thread and can have its
    # outstanding work cancelled — which is what the SteamGridDB manager does
    # when the API key turns out to be wrong.
    #
    # Ported from cartridges/store/managers/async_manager.py. Upstream uses
    # Gio.Task with a Gio.Cancellable; a Ruby Thread plus the same
    # Gio::Cancellable gives the cancellation semantics the managers rely on
    # without handing GLib a Ruby block to run on a foreign thread.
    class AsyncManager < Manager
      self.blocking = false

      attr_reader :cancellable

      def initialize
        super
        @cancellable = Gio::Cancellable.new
      end

      # Cancels every task for this manager. A new cancellable has to be made
      # before further tasks can run.
      def cancel_tasks = @cancellable.cancel

      # Resets the cancellable. Tasks already scheduled stop being
      # cancellable.
      def reset_cancellable = @cancellable = Gio::Cancellable.new

      # Processes the game on another thread, then reports back from it.
      def process_game(game, additional_data, callback)
        Thread.new do
          unless @cancellable.cancelled?
            run(game, additional_data)
          end
          callback.call(self)
        end
      end
    end
  end
end
