# frozen_string_literal: true

require "adwaita"
require "fileutils"
require "pathname"
require "tmpdir"
require_relative "shared"
require_relative "logging/setup"

module Cartridges
  # SaveCover turns whatever image an importer found into the one or two files
  # the library reads — <game_id>.gif for an animated cover, <game_id>.tiff for
  # a still one — and tells the live GameCover to pick the new file up.
  #
  # Ported from cartridges/utils/save_cover.py. Upstream resizes animated GIFs
  # frame by frame with Pillow; GdkPixbuf has no animated-GIF writer, so an
  # animated cover is carried through at its original size and scaled by the
  # Gtk::Picture that displays it.
  module SaveCover
    # The libtiff compression codes GdkPixbuf's TIFF saver accepts.
    TIFF_OPTION = "compression"

    class << self
      # Every file extension GdkPixbuf can load, which is what decides whether
      # an unresized cover can be used straight from disk.
      def pixbuf_extensions
        @pixbuf_extensions ||= GdkPixbuf::Pixbuf.formats.flat_map(&:extensions).uniq
      end

      # Normalises a cover into a temporary file this app can read back, from
      # either a path on disk or an in-memory pixbuf.
      def convert_cover(cover_path = nil, pixbuf: nil, resize: true)
        source_path(cover_path, pixbuf).then do |path|
          if path.nil?
            nil
          elsif usable_as_is?(cover_path, pixbuf, resize)
            Pathname.new(cover_path)
          else
            convert(path, resize)
          end
        end
      end

      # Writes a game's cover into the covers directory, replacing whatever
      # was there, and refreshes the cover the window is showing.
      def save_cover(game_id, cover_path)
        FileUtils.mkdir_p(Shared::COVERS_DIR)

        animated_path = Shared::COVERS_DIR / "#{game_id}.gif"
        static_path = Shared::COVERS_DIR / "#{game_id}.tiff"

        FileUtils.rm_f([animated_path.to_s, static_path.to_s])

        if cover_path
          destination(cover_path, animated_path, static_path).then do |target|
            FileUtils.cp(cover_path.to_s, target.to_s)
            refresh_live_cover(game_id, target)
          end
        end
      end

      private

        def destination(cover_path, animated_path, static_path)
          File.extname(cover_path.to_s) == ".gif" ? animated_path : static_path
        end

        def refresh_live_cover(game_id, target)
          Shared.win&.game_covers&.[](game_id)&.new_cover(target)
        end

        def source_path(cover_path, pixbuf)
          if cover_path
            Pathname.new(cover_path)
          elsif pixbuf
            write_pixbuf(pixbuf)
          end
        end

        # An already-loadable file that does not need resizing is used where
        # it lies, which saves a re-encode of every official cover.
        def usable_as_is?(cover_path, pixbuf, resize)
          !resize && cover_path && !pixbuf &&
            pixbuf_extensions.include?(File.extname(cover_path.to_s).downcase.delete_prefix("."))
        end

        def write_pixbuf(pixbuf)
          temp_path(".tiff").tap { |path| pixbuf.save(path.to_s, "tiff", tiff_options) }
        end

        def convert(path, resize)
          if animated?(path)
            carry_through(path)
          else
            convert_still(path, resize)
          end
        end

        # An animated cover keeps its frames, so it is copied rather than
        # re-encoded.
        def carry_through(path)
          temp_path(".gif").tap { |target| FileUtils.cp(path.to_s, target.to_s) }
        end

        def convert_still(path, resize)
          load_pixbuf(path).then do |pixbuf|
            if pixbuf.nil?
              nil
            else
              temp_path(".tiff").tap do |target|
                resized(pixbuf, resize).save(target.to_s, "tiff", tiff_options)
              end
            end
          end
        end

        def resized(pixbuf, resize)
          if resize
            pixbuf.scale_simple(Shared.image_size[0], Shared.image_size[1], :bilinear)
          else
            pixbuf
          end
        end

        # GdkPixbuf refuses some files Gdk's texture loader accepts (notably
        # the TIFFs Steam ships), so a failed load falls back to the texture
        # loader and converts the TIFF it writes out.
        def load_pixbuf(path)
          GdkPixbuf::Pixbuf.new(file: path.to_s)
        rescue GLib::Error
          via_texture(path)
        end

        def via_texture(path)
          Gdk::Texture.new(Gio::File.new_for_path(path.to_s)).then do |texture|
            temp_path(".tiff").then do |target|
              texture.save_to_tiff(target.to_s)
              GdkPixbuf::Pixbuf.new(file: target.to_s)
            end
          end
        rescue GLib::Error => e
          Logging.logger.warn("Could not read cover #{path}: #{e.message}")
          nil
        end

        def animated?(path)
          !GdkPixbuf::PixbufAnimation.new(path.to_s).static_image?
        rescue GLib::Error
          false
        end

        def tiff_options
          { TIFF_OPTION => compression }
        end

        def compression
          if Shared.schema.get_boolean("high-quality-images")
            Shared::HIGH_QUALITY_TIFF_COMPRESSION
          else
            Shared::TIFF_COMPRESSION
          end
        end

        def temp_path(suffix)
          Pathname.new(Dir.mktmpdir("cartridges-cover")) / "cover#{suffix}"
        end
    end
  end
end
