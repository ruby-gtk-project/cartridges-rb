# frozen_string_literal: true

require "adwaita"
require "shellwords"
require_relative "shared"
require_relative "game_model"
require_relative "game_cover"
require_relative "create_dialog"
require_relative "save_cover"
require_relative "store/managers/sgdb_manager"

module Cartridges
  # DetailsDialog is the add/edit form: the cover with its edit and delete
  # buttons, and the name/developer/executable entry rows. Applying it either
  # creates a new "imported" game or updates the one it was opened for.
  #
  # Ported from cartridges/details_dialog.py and data/gtk/details-dialog.blp.
  # Upstream leans on Pillow to normalise a picked cover file; this port
  # reuses lib/cartridges/save_cover.rb's GdkPixbuf-based conversion instead.
  class DetailsDialog < Adwaita::Dialog
    class << self
      attr_accessor :open_instance
    end

    attr_reader :game, :game_cover

    def initialize(game = nil)
      super()
      self.class.open_instance = self
      signal_connect("closed") { self.class.open_instance = nil }

      @game = game
      @cover_changed = false
      @game_cover = GameCover.new([cover])

      build
      set_initial_values
    end

    def self.open? = !open_instance.nil?

    def build
      self.child = toolbar_view
      self
    end

    def set_initial_values
      if @game
        self.title = "Game Details"
        name_row.text = @game.name
        developer_row.text = @game.developer.to_s
        executable_row.text = @game.executable.to_s
        apply_button.label = "Apply"
        @game_cover.new_cover(@game.cover_path)
        delete_cover_revealer.reveal_child = !!@game_cover.get_texture
      else
        self.title = "Add New Game"
        apply_button.label = "Add"
      end
    end

    def apply_preferences
      name = name_row.text.to_s
      executable = executable_row.text.to_s

      if name.empty?
        CreateDialog.call(self, "Couldn't Add Game", "Game title cannot be empty.")
        return
      elsif executable.empty?
        CreateDialog.call(self, "Couldn't Add Game", "Executable cannot be empty.")
        return
      end

      @game ||= build_new_game

      @game.name = name
      @game.developer = developer_row.text.to_s.empty? ? nil : developer_row.text.to_s
      @game.executable = executable

      Shared.win.game_covers[@game.game_id] = @game_cover
      SaveCover.save_cover(@game.game_id, @game_cover.path) if @cover_changed

      Shared.store.add_game(@game, {}, run_pipeline: false)
      @game.save
      @game.update

      fetch_cover_if_missing

      @game_cover.pictures.delete(cover)
      close
      Shared.win.show_details_page(@game)
    end

    def choose_cover
      Gtk::FileDialog.new.tap do |dialog|
        dialog.open(root, nil) do |_source, result|
          apply_cover(dialog.open_finish(result)&.path)
        rescue GLib::Error
          nil
        end
      end
    end

    def choose_executable
      Gtk::FileDialog.new.tap do |dialog|
        dialog.open(root, nil) do |_source, result|
          path = dialog.open_finish(result)&.path
          executable_row.text = Shellwords.escape(path) if path
        rescue GLib::Error
          nil
        end
      end
    end

    def delete_cover
      @game_cover.new_cover
      delete_cover_revealer.reveal_child = false
      @cover_changed = true
    end

    private

      def build_new_game
        number = (Shared.store.source_games["imported"]&.keys || [])
                 .filter_map { |id| id[/^imported_(\d+)$/, 1]&.to_i }.max.to_i + 1

        GameModel.new(
          "game_id" => "imported_#{number}",
          "hidden" => false,
          "source" => "imported",
          "added" => Time.now.to_i,
        )
      end

      def fetch_cover_if_missing
        return if @game_cover.get_texture

        @game.set_loading(1)
        manager = Shared.store.managers[Store::SgdbManager]
        return unless manager

        manager.reset_cancellable
        manager.process_game(@game, {}, ->(_mgr) { cover_fetch_done })
      end

      def cover_fetch_done
        @game.set_loading(-1)
        @game.update
      end

      def apply_cover(path)
        new_path = SaveCover.convert_cover(path)
        if new_path
          @game_cover.new_cover(new_path)
          delete_cover_revealer.reveal_child = true
          @cover_changed = true
        end
      end

      # Memoized widget methods

      def toolbar_view
        @toolbar_view ||= Adwaita::ToolbarView.new.tap do |view|
          view.add_top_bar(Adwaita::HeaderBar.new)
          view.content = content_box
        end
      end

      def content_box
        @content_box ||= Gtk::Box.new(:vertical, 18).tap do |box|
          box.margin_top = 12
          box.margin_bottom = 24
          box.margin_start = 24
          box.margin_end = 24
          box.append(cover_overlay)
          box.append(fields_group)
          box.append(apply_button)
        end
      end

      def cover_overlay
        @cover_overlay ||= Gtk::Overlay.new.tap do |o|
          o.child = cover
          o.add_overlay(spinner)
          o.add_overlay(edit_cover_button)
          o.add_overlay(delete_cover_revealer)
        end
      end

      def spinner = @spinner ||= Adwaita::Spinner.new.tap { |s| s.visible = false }

      def cover
        @cover ||= Gtk::Picture.new.tap do |p|
          p.width_request = 200
          p.height_request = 300
          p.add_css_class("card")
        end
      end

      def edit_cover_button
        @edit_cover_button ||= Gtk::Button.new.tap do |btn|
          btn.icon_name = "document-edit-symbolic"
          btn.halign = :end
          btn.valign = :end
          btn.add_css_class("circular")
          btn.add_css_class("osd")
          btn.signal_connect("clicked") { choose_cover }
        end
      end

      def delete_cover_revealer
        @delete_cover_revealer ||= Gtk::Revealer.new.tap do |r|
          r.halign = :start
          r.valign = :end
          r.child = delete_cover_button
        end
      end

      def delete_cover_button
        @delete_cover_button ||= Gtk::Button.new.tap do |btn|
          btn.icon_name = "user-trash-symbolic"
          btn.add_css_class("circular")
          btn.add_css_class("osd")
          btn.signal_connect("clicked") { delete_cover }
        end
      end

      def fields_group
        @fields_group ||= Gtk::ListBox.new.tap do |list|
          list.selection_mode = :none
          list.add_css_class("boxed-list")
          list.append(name_row)
          list.append(developer_row)
          list.append(executable_row_box)
        end
      end

      def name_row
        @name_row ||= Adwaita::EntryRow.new.tap do |row|
          row.title = "Name"
        end
      end

      def developer_row
        @developer_row ||= Adwaita::EntryRow.new.tap do |row|
          row.title = "Developer"
        end
      end

      def executable_row_box
        @executable_row_box ||= Adwaita::EntryRow.new.tap do |row|
          row.title = "Executable"
          row.add_suffix(file_chooser_button)
        end
      end

      def executable_row = executable_row_box

      def file_chooser_button
        @file_chooser_button ||= Gtk::Button.new.tap do |btn|
          btn.icon_name = "document-open-symbolic"
          btn.valign = :center
          btn.add_css_class("flat")
          btn.signal_connect("clicked") { choose_executable }
        end
      end

      def apply_button
        @apply_button ||= Gtk::Button.new.tap do |btn|
          btn.halign = :center
          btn.add_css_class("pill")
          btn.add_css_class("suggested-action")
          btn.signal_connect("clicked") { apply_preferences }
        end
      end
  end
end
