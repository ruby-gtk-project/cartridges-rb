# frozen_string_literal: true

require "fileutils"
require "pathname"
require "zlib"

module Cartridges
  module Logging
    # SessionFileHandler writes the log of one app session to its own file.
    # On start-up the existing logs are compressed, their numeric suffix is
    # bumped, and anything past backup_count is deleted — so the log directory
    # holds this session's plain file plus a couple of compressed older ones.
    # Those are the files the About dialog's debug information is made of.
    #
    # Ported from cartridges/logging/session_file_handler.py. Upstream
    # compresses with LZMA, which Ruby's standard library does not carry;
    # gzip through Zlib is the equivalent that needs no extra gem, so the
    # rotated files end in .gz rather than .xz.
    class SessionFileHandler
      # Position of the number suffix in "cartridges.1.log.gz".
      NUMBER_SUFFIX_POSITION = 1

      COMPRESSED_SUFFIX = ".gz"

      attr_reader :filename, :backup_count, :log_file

      def initialize(filename, backup_count: 2)
        @filename = Pathname.new(filename)
        @backup_count = backup_count
        create_dir
        rotate
        @log_file = File.open(@filename, "w")
        @log_file.sync = true
      end

      def write(message) = @log_file.write(message)

      def close
        unless @log_file.closed?
          @log_file.close
        end
      end

      def create_dir = FileUtils.mkdir_p(@filename.dirname)

      def logfile?(path)
        path.file? && path.basename.to_s.start_with?(@filename.basename(".*").to_s)
      end

      # The log files, newest-numbered first, which is the order the rotation
      # has to walk them in so a rename never lands on an existing name.
      def logfiles
        @filename.dirname.children.select { |path| logfile?(path) }
                 .sort_by { |path| -path_number(path) }
      end

      def suffixes(path) = path.basename.to_s.scan(/\.[^.]+/)

      def path_number?(path)
        suffixes(path)[NUMBER_SUFFIX_POSITION].to_s.delete_prefix(".").match?(/\A\d+\z/)
      end

      def path_number(path)
        if path_number?(path)
          suffixes(path)[NUMBER_SUFFIX_POSITION].delete_prefix(".").to_i
        else
          0
        end
      end

      # Sets or replaces the number suffix, keeping the rest of the name.
      def with_number(path, number)
        suffixes(path).then do |parts|
          if path_number?(path)
            parts.delete_at(NUMBER_SUFFIX_POSITION)
          end
          parts.insert(NUMBER_SUFFIX_POSITION, ".#{number}")
          path.basename.to_s.split(".", 2).first + parts.join
        end
      end

      def rotate = logfiles.each { |path| rotate_file(path) }

      def rotate_file(path)
        compress(path).then do |compressed|
          if compressed
            (path_number(compressed) + 1).then do |number|
              compressed.dirname.then do |dir|
                FileUtils.mv(compressed.to_s, (dir / with_number(compressed, number)).to_s)
                if number > @backup_count
                  FileUtils.rm_f((dir / with_number(compressed, number)).to_s)
                end
              end
            end
          end
        end
      end

      # Compresses an uncompressed log, returning the path to compress-or-keep,
      # or nil when the file was corrupt and thrown away.
      def compress(path)
        if path.basename.to_s.end_with?(COMPRESSED_SUFFIX)
          path
        else
          compress_plain(path)
        end
      end

      private

        def compress_plain(path)
          File.read(path, encoding: "UTF-8").then do |data|
            unless data.valid_encoding?
              raise ArgumentError, "invalid log encoding"
            end

            Pathname.new("#{path}#{COMPRESSED_SUFFIX}").tap do |compressed|
              Zlib::GzipWriter.open(compressed.to_s) { |gz| gz.write(data) }
              path.unlink
            end
          end
        rescue ArgumentError, Errno::ENOENT
          FileUtils.rm_f(path.to_s)
          nil
        end
    end
  end
end
