# frozen_string_literal: true

require "adwaita"
require "pathname"
require "tmpdir"
require_relative "manager"
require_relative "steam_api_manager"
require_relative "../../save_cover"
require_relative "../../http_client"
require_relative "../../shared"

module Cartridges
  class Store
    # ImageSize is a width/height pair with the arithmetic the compositing
    # code does on it.
    #
    # Ported from the ImageSize NamedTuple in
    # cartridges/store/managers/cover_manager.py.
    ImageSize = Data.define(:width, :height) do
      def aspect_ratio = width.to_f / height
      def to_s = "#{width}x#{height}"
      def to_a = [width, height]
      def to_ints = [width.round, height.round]

      def *(scale) = ImageSize.new(width: width * scale, height: height * scale)
      def /(divisor) = self * (1.0 / divisor)
      def +(other) = ImageSize.new(width: width + other.width, height: height + other.height)
      def -(other) = self + (other * -1)

      def element_wise_div(other)
        ImageSize.new(width: width.to_f / other.width, height: height.to_f / other.height)
      end

      def element_wise_mul(other)
        ImageSize.new(width: width * other.width, height: height * other.height)
      end

      def invert = ImageSize.new(width: 1, height: 1).element_wise_div(self)
    end

    # CoverManager puts a cover on a game. The order of priority is the local
    # cover, then the icon, then the online cover; each is composited over a
    # blurred copy of itself unless it is close enough to the cover's aspect
    # ratio to simply stretch.
    #
    # Ported from cartridges/store/managers/cover_manager.py.
    class CoverManager < Manager
      self.run_after = [SteamAPIManager]
      self.retryable_on = HttpClient::RETRYABLE

      # How much taller-than-cover an image may be stretched before it gets
      # the blurred background instead.
      MAX_STRETCH = 0.12

      # The keys an importer may leave an image under, in priority order.
      IMAGE_KEYS = %w[local_image_path local_icon_path online_cover_url].freeze

      # An icon is smaller than a cover and squarer, so it is inset and gets a
      # taller blur.
      ICON_SCALE = 0.7
      ICON_BLUR_SIZE = ImageSize.new(width: 1, height: 2)

      DEFAULT_BLUR_SIZE = ImageSize.new(width: 2, height: 2)

      def main(game, additional_data)
        unless game.blacklisted?
          IMAGE_KEYS.each do |key|
            if apply_image(game, key, lookup(additional_data, key))
              break
            end
          end
        end
      end

      # Downloads an online cover into a temporary file.
      def download_image(url)
        HttpClient.get(url).raise_for_status!.then do |response|
          (Pathname.new(Dir.mktmpdir("cartridges-cover-dl")) / "cover").tap do |path|
            path.binwrite(response.body)
          end
        end
      end

      # An image taller than the cover is always stretched; a wider one only
      # if the squash stays under MAX_STRETCH.
      def stretchable?(source_size, cover_size)
        if source_size.aspect_ratio < cover_size.aspect_ratio
          true
        else
          resized_height = (1 / source_size.aspect_ratio) * cover_size.width
          (1 - (resized_height / cover_size.height)) <= MAX_STRETCH
        end
      end

      # The image composited over a blurred, cover-sized copy of itself,
      # centred and scaled to fit.
      def composite_cover(image_path, scale: 1, blur_size: DEFAULT_BLUR_SIZE)
        load_source(image_path).then do |source|
          ImageSize.new(width: source.width, height: source.height).then do |source_size|
            ImageSize.new(width: Shared.image_size[0], height: Shared.image_size[1]).then do |cover_size|
              if scale == 1 && stretchable?(source_size, cover_size)
                source
              else
                composite(source, source_size, cover_size, scale, blur_size)
              end
            end
          end
        end
      end

      private

        def lookup(additional_data, key)
          additional_data[key] || additional_data[key.to_sym]
        end

        def apply_image(game, key, value)
          if value.nil? || value.to_s.empty?
            false
          else
            image_for(key, value).then do |image_path|
              if image_path&.file?
                store(game, key, image_path)
                true
              else
                false
              end
            end
          end
        end

        def image_for(key, value)
          if key == "online_cover_url"
            download_image(value)
          else
            Pathname.new(value.to_s)
          end
        end

        def store(game, key, image_path)
          composited(key, image_path).then do |pixbuf|
            SaveCover.save_cover(game.game_id, SaveCover.convert_cover(pixbuf: pixbuf))
          end
        end

        def composited(key, image_path)
          if key == "local_icon_path"
            composite_cover(image_path, scale: ICON_SCALE, blur_size: ICON_BLUR_SIZE)
          else
            composite_cover(image_path)
          end
        end

        def load_source(image_path)
          GdkPixbuf::Pixbuf.new(file: SaveCover.convert_cover(image_path, resize: false).to_s)
        end

        def composite(source, source_size, cover_size, scale, blur_size)
          blurred(source, blur_size, cover_size).then do |cover|
            uniform_scale(cover_size, source_size, scale).then do |factor|
              (source_size * factor).then do |inner_size|
                ((cover_size - inner_size) / 2).then do |position|
                  draw(source, cover, position, inner_size, factor)
                  cover
                end
              end
            end
          end
        end

        def blurred(source, blur_size, cover_size)
          source.scale_simple(*blur_size.to_ints, :bilinear)
                .scale_simple(*cover_size.to_ints, :bilinear)
        end

        def uniform_scale(cover_size, source_size, scale)
          scale * cover_size.element_wise_div(source_size).to_a.min
        end

        def draw(source, cover, position, inner_size, factor)
          source.composite(
            cover,
            position.width.round,
            position.height.round,
            inner_size.width.round,
            inner_size.height.round,
            position.width,
            position.height,
            factor,
            factor,
            :bilinear,
            255,
          )
        end
    end
  end
end
