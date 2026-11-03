# frozen_string_literal: true

require "fileutils"
require "tmpdir"
require "pathname"

module Cartridges
  # Sqlite copies a SQLite database and its sidecar files (-wal, -shm,
  # -journal) into a fresh temporary directory, so the importers read a
  # snapshot instead of a file the owning app may be writing to.
  #
  # Ported from cartridges/utils/sqlite.py. The caller owns the returned
  # path's parent directory and is in charge of deleting it.
  module Sqlite
    module_function

    def copy_db(original_path)
      Pathname.new(original_path).then do |original|
        Pathname.new(Dir.mktmpdir("cartridges-db")).then do |tmp|
          sidecars(original).each { |file| FileUtils.cp(file.to_s, (tmp / file.basename).to_s) }
          tmp / original.basename
        end
      end
    end

    # The database plus anything whose name starts with it. The name is escaped
    # because a game library path may legitimately contain glob characters.
    def sidecars(original)
      Pathname.glob("#{escape(original.to_s)}*").select { |path| path.file? }
    end

    def escape(pattern) = pattern.gsub(/([\*\?\[\]\{\}\\])/) { "\\#{::Regexp.last_match(1)}" }
  end
end
