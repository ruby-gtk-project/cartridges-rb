# frozen_string_literal: true

require "adwaita"
require "set"
require_relative "location"
require_relative "../error_producer"
require_relative "../friendly_error"
require_relative "../shared"
require_relative "../game_model"
require_relative "../store/managers/async_manager"
require_relative "../store/pipeline"
require_relative "../logging/setup"

module Cartridges
  module Importer
    # Importer runs every added source on its own thread, feeds whatever
    # each one produces into the store, and shows a progress dialog while
    # every game's pipeline finishes — then an error dialog for anything
    # that went wrong, and a summary toast with an undo button.
    #
    # Ported from cartridges/importer/importer.py. Gio.Task's thread pool is
    # replaced by a plain Ruby Thread per source, and the GLib.timeout_add
    # polling loops that watch for completion are kept as-is since this port
    # has no equivalent to Gio.Task's own completion callback.
    class Importer
      include ErrorProducer

      attr_reader :sources, :game_pipelines, :removed_game_ids, :imported_game_ids

      @summary_toast = nil

      class << self
        attr_accessor :summary_toast
      end

      def initialize
        Shared.import_time = Time.now.to_i
        Shared.store.new_game_ids.clear
        Shared.store.duplicate_game_ids.clear

        @removed_game_ids = Set.new
        @imported_game_ids = Set.new
        @game_pipelines = Set.new
        @sources = Set.new
        @n_source_tasks_created = 0
        @n_source_tasks_done = 0
        @n_pipelines_done = 0
      end

      def add_source(source) = @sources.add(source)

      def n_games_added
        @game_pipelines.count { |pipeline| !(pipeline.game.blacklisted? || pipeline.game.removed?) }
      end

      def pipelines_progress
        return 0.0 if @game_pipelines.empty?

        @game_pipelines.sum(&:progress) / @game_pipelines.size.to_f
      end

      def sources_progress
        return 0.0 if @n_source_tasks_created.zero?

        @n_source_tasks_done.to_f / @n_source_tasks_created
      end

      def finished?
        @n_source_tasks_created == @n_source_tasks_done && @game_pipelines.size == @n_pipelines_done
      end

      def run
        win = Shared.win
        app = win.application

        Shared.app_state = AppState::IMPORT

        self.class.summary_toast&.dismiss

        app.lookup_action("import").enabled = false
        app.lookup_action("add_game").enabled = false
        app.lookup_action("preferences").enabled = false

        @n_pipelines_done = 0
        @n_source_tasks_done = 0

        create_dialog(win)
        GLib::Timeout.add(100) { monitor_import }
        GLib::Timeout.add(100) { watchdog }

        reset_managers

        @sources.each do |source|
          Logging.logger.debug("Importing games from source #{source.source_id}")
          @n_source_tasks_created += 1
          Thread.new { source_task_thread_func(source) }
        end
      end

      def undo_import
        @imported_game_ids.each { |id| undo_one(id, removed: true) }
        @removed_game_ids.each { |id| undo_one(id, removed: false) }

        @imported_game_ids = Set.new
        @removed_game_ids = Set.new
        self.class.summary_toast&.dismiss
        Logging.logger.info("Import undone")
      end

      private

        def undo_one(id, removed:)
          game = Shared.store.get(id)
          return unless game

          game.removed = removed
          game.update
          game.save
        end

        def reset_managers
          collect_errors
          Shared.store.managers.each_value do |manager|
            manager.collect_errors
            manager.reset_cancellable if manager.is_a?(Store::AsyncManager)
          end
        end

        # Workaround for the same Adwaita bug upstream works around: the
        # dialog refuses to close if closed too soon after opening.
        def watchdog
          return true unless finished?

          @import_dialog.force_close
          false
        end

        def monitor_import
          unless finished?
            update_progressbar
            return true
          end

          finish_import
          false
        end

        def finish_import
          Logging.logger.info("Import done")
          remove_missing_games
          @imported_game_ids = Shared.store.new_game_ids.dup
          Shared.store.new_game_ids.clear
          Shared.store.duplicate_game_ids.clear

          @import_dialog.force_close

          app = Shared.win.application
          self.class.summary_toast = create_summary_toast
          create_error_dialog
          app.lookup_action("import").enabled = true
          app.lookup_action("add_game").enabled = true
          app.lookup_action("preferences").enabled = true
          Shared.app_state = AppState::DEFAULT
          Shared.win.create_source_rows
        end

        def remove_missing_games
          return unless Shared.schema.get_boolean("remove-missing")

          keys = Shared.schema.list_keys
          Shared.store.each { |game| maybe_remove_missing(game, keys) }
        end

        def maybe_remove_missing(game, keys)
          return if game.removed?
          return if game.source == "imported"
          return if keys.include?(game.base_source) && !Shared.schema.get_boolean(game.base_source)
          return if Shared.store.duplicate_game_ids.include?(game.game_id)
          return if Shared.store.new_game_ids.include?(game.game_id)

          Logging.logger.debug("Removing missing game #{game.name} (#{game.game_id})")
          game.removed = true
          game.save
          game.update
          @removed_game_ids.add(game.game_id)
        end

        # --- Thread code: nothing here touches the GUI ---------------------

        def source_task_thread_func(source)
          unless source.available?
            Logging.logger.info("Source #{source.source_id} skipped, not available")
            @n_source_tasks_done += 1
            return
          end

          scan_source(source)
          Logging.logger.debug("Import done for source #{source.source_id}")
          @n_source_tasks_done += 1
        end

        def scan_source(source)
          source.each { |result| handle_result(source, result) }
        rescue UnresolvableLocationError
          Logging.logger.info("Source #{source.source_id} skipped, bad location")
        rescue StandardError => e
          Logging.logger.error("#{e.class.name} in #{source.source_id}: #{e.message}")
          report_error(e)
        end

        def handle_result(source, result)
          game, additional_data = result.is_a?(Array) ? result : [result, {}]
          return unless game

          pipeline = Shared.store.add_game(game, additional_data)
          return unless pipeline

          Logging.logger.info("Imported #{game.name} (#{game.game_id})")
          pipeline.signal_connect("advanced") { |p| @n_pipelines_done += 1 if p.done? }
          @game_pipelines.add(pipeline)
        rescue StandardError => e
          Logging.logger.error("#{e.class.name} in #{source.source_id}: #{e.message}")
          report_error(e)
        end

        # --- GUI code --------------------------------------------------------

        def create_dialog(win)
          @progressbar = Gtk::ProgressBar.new.tap do |bar|
            bar.margin_start = 12
            bar.margin_end = 12
          end

          @import_statuspage = Adwaita::StatusPage.new.tap do |page|
            page.title = "Importing Games…"
            page.child = @progressbar
          end

          @import_dialog = Adwaita::Dialog.new.tap do |dialog|
            dialog.child = @import_statuspage
            dialog.content_width = 350
            dialog.can_close = false
            dialog.signal_connect("close-attempt") { |*_args| win.window.close }
            dialog.present(win.window)
          end
        end

        def update_progressbar
          @progressbar.fraction = (0.1 * sources_progress) + (0.9 * pipelines_progress)
        end

        def create_error_dialog
          errors = (collect_errors + Shared.store.managers.values.flat_map(&:collect_errors))
                   .select { |error| error.is_a?(FriendlyError) }
                   .map { |error| [error.title, error.subtitle] }
                   .uniq

          return timeout_toast if errors.empty?

          present_error_dialog(errors)
        end

        def present_error_dialog(errors)
          Adwaita::AlertDialog.new.tap do |dialog|
            dialog.heading = "Warning"
            dialog.add_response("close", "Dismiss")
            dialog.add_response("open_preferences_import", "Preferences")
            dialog.set_default_response("open_preferences_import")
            dialog.signal_connect("response") { |_widget, response| dialog_response_callback(response) }

            if errors.size == 1
              dialog.heading = errors.first[0]
              dialog.body = errors.first[1]
            else
              dialog.body = "The following errors occured during import:"
              dialog.extra_child = error_list_box(errors)
            end

            dialog.present(Shared.win.window)
          end
        end

        def error_list_box(errors)
          Gtk::ListBox.new.tap do |list|
            list.selection_mode = :none
            list.add_css_class("boxed-list")
            list.margin_top = 9
            errors.each do |title, subtitle|
              list.append(
                Adwaita::ActionRow.new.tap do |row|
                  row.title = title
                  row.subtitle = subtitle
                end,
              )
            end
          end
        end

        def create_summary_toast
          toast = Adwaita::Toast.new("").tap do |t|
            t.timeout = 0
            t.priority = :high
          end

          title = summary_title(toast)
          toast.title = title

          Shared.win.toast_overlay.add_toast(toast) unless skip_toast?
          toast
        end

        def skip_toast?
          n_games_added.zero? && @removed_game_ids.empty? && Shared.schema.get_boolean("auto-import")
        end

        def summary_title(toast)
          title =
            if n_games_added.zero?
              no_games_added_title(toast)
            else
              "#{n_games_added} #{n_games_added == 1 ? "game" : "games"} imported"
            end

          title += ", #{@removed_game_ids.size} removed" unless @removed_game_ids.empty?

          if n_games_added.positive? || !@removed_game_ids.empty?
            toast.button_label = "Undo"
            toast.signal_connect("button-clicked") { undo_import }
          end

          title
        end

        def no_games_added_title(toast)
          if @removed_game_ids.empty?
            toast.button_label = "Preferences"
            toast.signal_connect("button-clicked") { dialog_response_callback("open_preferences") }
          end
          "No new games found"
        end

        def timeout_toast
          toast = self.class.summary_toast
          return unless toast

          GLib::Timeout.add_seconds(5) do
            toast.dismiss
            false
          end
        end

        def dialog_response_callback(response)
          case response
          when "open_preferences"
            Shared.win.application.on_preferences_action
          when "open_preferences_import"
            Shared.win.application.on_preferences_action
            timeout_toast
          else
            timeout_toast
          end
        end
    end
  end
end
