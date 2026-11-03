# frozen_string_literal: true

require "adwaita"
require "pathname"
require "set"
require_relative "shared"

module Cartridges
  # GameCover owns one game's cover art and every Gtk::Picture showing it: the
  # still texture, the animation (and the timeout that advances it), and the
  # blurred copy plus the two luminance values that drive the details page's
  # backdrop and the readability of the text over it.
  #
  # Ported from cartridges/game_cover.py. Upstream blurs with Pillow's
  # GaussianBlur and reads the statistics off a greyscale copy; GdkPixbuf has
  # no blur filter, so the blur is the usual downscale-then-upscale pair and
  # the luminance statistics are computed from the blurred pixels directly.
  class GameCover
    # The size the blurred backdrop is rendered at, as upstream.
    BLUR_SIZE = [100, 150].freeze

    # The intermediate size the downscale blur passes through. Upstream's
    # GaussianBlur radius of 20 over a 100x150 image flattens it to about
    # this much detail.
    BLUR_DETAIL = [5, 8].freeze

    # Luminance the placeholder backdrop reports, for light and dark mode.
    PLACEHOLDER_LUMINANCE = [0.3, 0.5].freeze

    DATA_DIR = Pathname.new(File.expand_path("../../data", __dir__))

    attr_reader :pictures, :path, :animation, :blurred, :luminance, :texture

    class << self
      def placeholder = @placeholder ||= load_texture(DATA_DIR / "library_placeholder.svg")
      def placeholder_small = @placeholder_small ||= load_texture(DATA_DIR / "library_placeholder_small.svg")

      def load_texture(path)
        Gdk::Texture.new(Gio::File.new_for_path(path.to_s))
      end
    end

    def initialize(pictures, path = nil)
      @pictures = Set.new(Array(pictures))
      new_cover(path)
    end

    # Points the cover at a new file (or at nothing), dropping whatever was
    # cached for the old one.
    def new_cover(path = nil)
      @animation = nil
      @texture = nil
      @blurred = nil
      @luminance = nil
      @path = path && Pathname.new(path)

      if @path
        load_path(@path)
      end

      unless @animation
        self.texture = @texture
      end
    end

    # The still image for the cover: an animation's first frame, or the
    # texture.
    def get_texture
      if @animation
        Gdk::Texture.new(@animation.static_image)
      else
        @texture
      end
    end

    # The blurred backdrop, computed once and kept. Also fills in the two
    # luminance values the details page uses to pick its text colour.
    def get_blurred
      unless @blurred
        if @path
          blur_path
        else
          @blurred = self.class.placeholder_small
          @luminance = PLACEHOLDER_LUMINANCE
        end
      end
      @blurred
    end

    # Adds another Gtk::Picture to the set this cover paints into.
    def add_picture(picture)
      @pictures.add(picture)
      if @animation
        update_animation(@animation)
      else
        self.texture = @texture
      end
    end

    # Paints a texture into every picture still on screen, dropping the ones
    # that are not, and stopping the animation once none are left.
    def texture=(texture)
      @pictures.delete_if { |picture| !picture.visible? }
      if @pictures.empty?
        @animation = nil
      else
        @pictures.each do |picture|
          picture.paintable = texture || self.class.placeholder
          picture.queue_draw
        end
      end
    end

    # Advances an animation by one frame and schedules the next, as long as
    # the animation it was started for is still the current one.
    def update_animation(animation)
      if @animation.equal?(animation)
        @anim_iter.advance
        self.texture = Gdk::Texture.new(@anim_iter.pixbuf)
        GLib::Timeout.add([@anim_iter.delay_time, 20].max) do
          update_animation(animation)
          GLib::Source::REMOVE
        end
      end
    end

    private

      def load_path(path)
        if path.extname == ".gif"
          @animation = GdkPixbuf::PixbufAnimation.new(path.to_s)
          @anim_iter = @animation.get_iter
          update_animation(@animation)
        else
          @texture = Gdk::Texture.new(Gio::File.new_for_path(path.to_s))
        end
      rescue GLib::Error
        @animation = nil
        @texture = nil
      end

      def blur_path
        blurred_pixbuf.then do |pixbuf|
          if pixbuf
            @blurred = Gdk::Texture.new(pixbuf)
            @luminance = luminance_of(pixbuf)
          else
            @blurred = self.class.placeholder_small
            @luminance = PLACEHOLDER_LUMINANCE
          end
        end
      end

      # The blur: scale right down, then back up, both bilinear, which leaves
      # a smooth gradient with none of the original detail.
      def blurred_pixbuf
        GdkPixbuf::Pixbuf.new(file: @path.to_s)
                         .scale_simple(BLUR_DETAIL[0], BLUR_DETAIL[1], :bilinear)
                         .scale_simple(BLUR_SIZE[0], BLUR_SIZE[1], :bilinear)
      rescue GLib::Error
        nil
      end

      # The pair of luminance values upstream derives from the greyscale
      # statistics: one clamped for light mode, one for dark.
      def luminance_of(pixbuf)
        greys(pixbuf).then do |values|
          (values.sum.to_f / values.length).then do |mean|
            [
              [(mean + values.min) / 510, 0.7].min,
              [(mean + values.max) / 510, 0.3].max,
            ]
          end
        end
      end

      # The ITU-R 601-2 luma transform, which is the one Pillow's "L"
      # conversion uses.
      def greys(pixbuf)
        pixbuf.pixels.then do |bytes|
          (0...pixbuf.height).flat_map do |row|
            row_greys(bytes, row * pixbuf.rowstride, pixbuf.width, pixbuf.n_channels)
          end
        end
      end

      # Rows are padded to the pixbuf's rowstride, so each row is walked from
      # its own offset rather than straight through the byte array.
      def row_greys(bytes, offset, width, channels)
        (0...width).map do |column|
          (offset + (column * channels)).then do |at|
            ((bytes[at] * 299) + (bytes[at + 1] * 587) + (bytes[at + 2] * 114)) / 1000
          end
        end
      end
  end
end
