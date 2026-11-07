# frozen_string_literal: true

require "adwaita"
require_relative "manager"

module Cartridges
  class Store
    # AsyncManager is a Manager that runs on its own thread and can have its
    # outstanding work cancelled — which is what the SteamGridDB manager does
    # when the API key turns out to be wrong.
    #
    # Ported from cartridges/store/managers/async_manager.py. Upstream's
    # Gio.Task runs the work on a thread but — per GTask's own contract —
    # always delivers its completion callback back on the thread that
    # created the task, which here is always the GLib main thread. A plain
    # Ruby Thread has no such contract: calling `callback` directly from the
    # thread's block would hand it to Pipeline#manager_callback, whose
    # `advance` may synchronously run a *blocking* manager next (DisplayManager
    # touches GTK widgets) on that same worker thread — a GTK thread-safety
    # violation that only shows up as an intermittent hang or crash once a
    # source actually imports a game. `GLib::Idle.add` is what restores
    # Gio.Task's guarantee: it runs the block on the main loop's own thread.
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

      # Processes the game on another thread, then reports back on the main
      # thread, exactly as Gio::Task's own completion callback would.
      def process_game(game, additional_data, callback)
        Thread.new do
          unless @cancellable.cancelled?
            run(game, additional_data)
          end
          GLib::Idle.add { callback.call(self); false }
        end
      end
    end
  end
end
