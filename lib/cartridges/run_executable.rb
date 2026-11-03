# frozen_string_literal: true

require "shellwords"
require_relative "shared"
require_relative "logging/setup"

module Cartridges
  # RunExecutable starts a game's command line, detached from the app so
  # quitting Cartridges does not take the game with it.
  #
  # Ported from cartridges/utils/run_executable.py. Inside a Flatpak sandbox
  # the command is handed to the host through flatpak-spawn; everywhere else
  # the shell runs it directly, from the user's home directory.
  module RunExecutable
    module_function

    def call(executable)
      command(executable).tap do |args|
        Logging.logger.info("Launching `#{args}`")
        Process.detach(spawn_detached(args))
      end
    end

    def command(executable)
      if Shared.flatpak?
        "flatpak-spawn --host /bin/sh -c #{Shellwords.escape(executable.to_s)}"
      else
        executable.to_s
      end
    end

    def spawn_detached(args)
      Process.spawn(args, chdir: Shared::HOME.to_s, pgroup: true)
    rescue NotImplementedError
      # Windows has no process groups; spawn without the pgroup option there.
      Process.spawn(args, chdir: Shared::HOME.to_s)
    end
  end
end
