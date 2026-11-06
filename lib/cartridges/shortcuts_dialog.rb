# frozen_string_literal: true

require "adwaita"

module Cartridges
  # ShortcutsDialog lists the keyboard shortcuts, in the "General" and
  # "Games" sections upstream groups them into.
  #
  # Ported from data/gtk/shortcuts-dialog.blp. Upstream points each item at
  # an action name and lets GTK look up the bound accelerator; the Ruby
  # Adwaita::ShortcutsItem binding only accepts an accelerator positionally
  # (see .claude/skills/ruby-gtk), so the accelerators application.rb binds
  # to each action are spelled out here directly.
  class ShortcutsDialog < Adwaita::ShortcutsDialog
    SECTIONS = {
      "General" => [
        ["Search", "<Control>f"],
        ["Preferences", "<Control>comma"],
        ["Keyboard Shortcuts", "<Control>question"],
        ["Undo", "<Control>z"],
        ["Quit", "<Control>q"],
        ["Toggle Sidebar", "F9"],
        ["Main Menu", "F10"],
      ],
      "Games" => [
        ["Add Game", "<Control>n"],
        ["Import", "<Control>i"],
        ["Show Hidden Games", "<Control>h"],
        ["Remove Game", "Delete"],
      ],
    }.freeze

    def build
      tap do |dialog|
        SECTIONS.each { |title, items| dialog.add(section(title, items)) }
      end
    end

    private

      def section(title, items)
        Adwaita::ShortcutsSection.new.tap do |section|
          section.title = title
          items.each { |label, accelerator| section.add(item(label, accelerator)) }
        end
      end

      def item(label, accelerator) = Adwaita::ShortcutsItem.new(label, accelerator)
  end
end
