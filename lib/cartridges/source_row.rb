# frozen_string_literal: true

require "gtk4"

module Cartridges
  # SourceRow is one row of the sidebar's source list: an icon, the source's
  # display name, and a dimmed count of how many games are in it. One of
  # these is built per source the store has seen games from.
  #
  # Ported from the `row` Gtk::Box built in CartridgesWindow.create_source_rows
  # in cartridges/window.py, which has no counterpart in data/gtk/window.blp
  # because upstream builds it by hand too.
  class SourceRow < Gtk::Box
    attr_reader :source_id, :games_no

    def initialize(source_id, name, games_no)
      super(:horizontal, 12)
      @source_id = source_id
      @games_no = games_no

      self.margin_top = 12
      self.margin_bottom = 12
      self.margin_start = 6
      self.margin_end = 6

      append(icon)
      append(name_label.tap { |l| l.label = name })
      append(count_label.tap { |l| l.label = games_no.to_s })
    end

    def icon
      @icon ||= Gtk::Image.new(icon_name: icon_name)
    end

    def name_label
      @name_label ||= Gtk::Label.new.tap do |label|
        label.halign = :start
        label.wrap = true
        label.wrap_mode = :char
      end
    end

    def count_label
      @count_label ||= Gtk::Label.new.tap do |label|
        label.hexpand = true
        label.halign = :end
        label.add_css_class("dim-label")
      end
    end

    private

      # The icon upstream looks up as "{split_id}-source-symbolic", with
      # desktop entries using the generic application icon instead.
      def icon_name
        split_id = @source_id.to_s.split("_").first
        split_id == "desktop" ? "user-desktop-symbolic" : "#{split_id}-source-symbolic"
      end
  end
end
