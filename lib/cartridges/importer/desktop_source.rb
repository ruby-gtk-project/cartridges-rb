# frozen_string_literal: true

require "gtk4"
require "pathname"
require "shellwords"
require_relative "source"
require_relative "../game_model"
require_relative "../shared"

module Cartridges
  module Importer
    # DesktopSourceIterable scans every XDG applications directory for
    # desktop entries in the "Game" category, skipping the ones Lutris,
    # Steam, Heroic or Bottles already cover, and launches each through
    # whichever of `gio launch`, `gtk4-launch` or `gtk-launch` is available.
    #
    # Ported from the DesktopSourceIterable class in
    # cartridges/importer/desktop_source.py.
    class DesktopSourceIterable < SourceIterable
      SEARCH_PATHS = [
        Shared::HOST_DATA_DIR,
        "/run/host/usr/local/share",
        "/run/host/usr/share",
        "/run/host/usr/share/pixmaps",
        "/usr/share/pixmaps",
      ].freeze

      SKIP_PREFIXES = ["net.lutris."].freeze
      SKIP_EXECUTABLE_SUBSTRINGS = ["steam://rungameid/", "heroic://launch/", "bottles-cli "].freeze

      def each(&block)
        search_paths = SEARCH_PATHS + GLib.system_data_dirs
        icon_theme = build_icon_theme(search_paths)
        launch_command, full_path = check_launch_commands

        search_paths.each do |search_path|
          next if search_path.to_s.start_with?("/app/")

          applications_dir = Pathname.new(search_path.to_s) / "applications"
          next unless applications_dir.directory?

          applications_dir.children.each do |entry|
            next unless entry.extname == ".desktop"
            next if SKIP_PREFIXES.any? { |prefix| entry.basename.to_s.start_with?(prefix) }

            process_entry(entry, icon_theme, launch_command, full_path, block)
          end
        end
      end

      private

        def build_icon_theme(search_paths)
          Gtk::IconTheme.new.tap do |theme|
            search_paths.each do |search_path|
              path = search_path.to_s.end_with?("/pixmaps") ? Pathname.new(search_path.to_s) : Pathname.new(search_path.to_s) / "icons"
              theme.add_search_path(path.to_s) if path.directory? && !path.to_s.start_with?("/app/")
            end
          end
        end

        def process_entry(entry, icon_theme, launch_command, full_path, block)
          keyfile = load_keyfile(entry)
          return unless keyfile && admissible?(keyfile)

          name = string_or_nil(keyfile, "Name")
          executable = string_or_nil(keyfile, "Exec")&.split(" %")&.first
          return unless name && executable
          return if SKIP_EXECUTABLE_SUBSTRINGS.any? { |s| executable.include?(s) }

          real_entry = strip_run_host(entry)
          launch_arg = Shellwords.escape(full_path ? real_entry.to_s : real_entry.basename(".desktop").to_s)

          values = {
            "source" => source.source_id,
            "added" => Shared.import_time,
            "name" => name,
            "game_id" => "desktop_#{entry.basename(".desktop")}",
            "executable" => "#{launch_command} #{launch_arg}",
          }

          block.call([GameModel.new(values), icon_data(keyfile, icon_theme)])
        end

        def admissible?(keyfile)
          categories = string_list_or_empty(keyfile)
          categories.include?("Game") && try_exec_ok?(keyfile) && !no_display_or_hidden?(keyfile)
        end

        def string_list_or_empty(keyfile)
          keyfile.get_string_list("Desktop Entry", "Categories")
        rescue GLib::Error
          []
        end

        def string_or_nil(keyfile, key)
          keyfile.get_string("Desktop Entry", key)
        rescue GLib::Error
          nil
        end

        def load_keyfile(entry)
          GLib::KeyFile.new.tap { |file| file.load_from_file(entry.to_s, 0) }
        rescue GLib::Error
          nil
        end

        def try_exec_ok?(keyfile)
          try_exec = keyfile.get_string("Desktop Entry", "TryExec")
          try_exec.nil? || try_exec.empty? || check_command("which #{Shellwords.escape(try_exec)}")
        rescue GLib::Error
          true
        end

        def no_display_or_hidden?(keyfile)
          boolean_or_false(keyfile, "NoDisplay") || boolean_or_false(keyfile, "Hidden")
        end

        def boolean_or_false(keyfile, key)
          keyfile.get_boolean("Desktop Entry", key)
        rescue GLib::Error
          false
        end

        def strip_run_host(entry)
          prefix = "/run/host"
          entry.to_s.start_with?(prefix) ? Pathname.new(entry.to_s.delete_prefix(prefix)) : entry
        end

        def icon_data(keyfile, icon_theme)
          icon_str = string_or_nil(keyfile, "Icon")
          return {} unless icon_str

          if icon_str.include?("/")
            { "local_icon_path" => Pathname.new(icon_str) }
          else
            icon_path(icon_theme, icon_str).then { |path| path ? { "local_icon_path" => Pathname.new(path) } : {} }
          end
        end

        def icon_path(icon_theme, icon_str)
          icon_theme.lookup_icon(icon_str, nil, 512, 1, Shared.win&.window&.direction || :none, 0).file&.path
        rescue GLib::Error
          nil
        end

        def check_command(command)
          command = "flatpak-spawn --host /bin/sh -c #{Shellwords.escape(command)}" if Shared.flatpak?
          system(command, out: File::NULL, err: File::NULL)
        end

        def check_launch_commands
          [["gio launch", true, "gio help launch"], ["gtk4-launch", false, "which gtk4-launch"], ["gtk-launch", false, "which gtk-launch"]].each do |command, full_path, check|
            return [command, full_path] if check_command(check)
          end
          ["gtk-launch", false]
        end
    end

    # DesktopSource is the catch-all importer for installed applications
    # that advertise themselves as games through a standard .desktop entry.
    #
    # Ported from the DesktopSource class in
    # cartridges/importer/desktop_source.py.
    class DesktopSource < Source
      self.source_id = "desktop"
      self.source_name = "Desktop Entries"
      self.iterable_class = DesktopSourceIterable
      self.available_on = %w[linux]
    end
  end
end
