# frozen_string_literal: true

require_relative "location"
require_relative "../shared"

module Cartridges
  module Importer
    # SourceIterable is the data producer for one source of games: it yields
    # a game, or a game and the extra data the managers need, or nothing when
    # an iteration produced nothing, and is in charge of the per-game errors.
    #
    # Ported from the SourceIterable class in cartridges/importer/source.py.
    class SourceIterable
      include Enumerable

      attr_reader :source

      def initialize(source) = @source = source

      def each
        raise NotImplementedError, "#{self.class} must implement each"
      end
    end

    # Source is a place games come from: an installed app with a config file
    # listing game directories, a database, a directory of desktop entries.
    #
    # Ported from the Source class in cartridges/importer/source.py. Python's
    # str.format with named fields is spelled with Ruby's %{} placeholders, so
    # the id and executable formats read the same way.
    class Source
      include Enumerable

      class << self
        # Spelled source_name rather than name: a class-level `name` reader
        # would shadow Ruby's own Class#name, which every error message and
        # inspect output goes through.
        attr_writer :source_id, :source_name, :variant, :available_on, :iterable_class

        def source_id = inherited_attribute(:source_id, nil)
        def source_name = inherited_attribute(:source_name, nil)
        def variant = inherited_attribute(:variant, nil)
        def available_on = inherited_attribute(:available_on, [])
        def iterable_class = inherited_attribute(:iterable_class, nil)

        def inherited_attribute(attribute, default)
          if instance_variable_defined?(:"@#{attribute}")
            instance_variable_get(:"@#{attribute}")
          elsif superclass.respond_to?(attribute)
            superclass.public_send(attribute)
          else
            default
          end
        end
      end

      # Locations must be built per instance, never shared between them.
      attr_reader :locations

      def source_id = self.class.source_id
      def name = self.class.source_name
      def variant = self.class.variant
      def available_on = self.class.available_on
      def iterable_class = self.class.iterable_class

      # The source's name, with its variant in brackets when it has one.
      def full_name
        if variant
          "#{name} (#{variant})"
        else
          name
        end
      end

      # The format game ids are built with.
      def game_id_format = "#{source_id}_%{game_id}"

      def available? = available_on.any? { |platform| Shared.platform.start_with?(platform) }

      # The command that starts one of this source's games. Implemented by the
      # subclasses.
      def make_executable(**_arguments)
        raise NotImplementedError, "#{self.class} must implement make_executable"
      end

      # Resolves the mandatory locations, then iterates the source's games.
      def each(&block)
        locations_to_resolve.each { |location| resolve_location(location) }
        iterable_class.new(self).each(&block)
      end

      private

        # An optional location that will not resolve is skipped; a mandatory
        # one makes the whole source un-iterable.
        def resolve_location(location)
          location.resolve
        rescue UnresolvableLocationError => e
          unless e.optional
            raise UnresolvableLocationError.new(optional: false)
          end
        end

        # Locations are held in a hash keyed the way upstream's NamedTuple
        # fields are named, so a source reads `locations[:data]`.
        def locations_to_resolve = @locations.is_a?(Hash) ? @locations.values : Array(@locations)
    end

    # ExecutableFormatSource builds its games' commands from a single format
    # string.
    #
    # Ported from the ExecutableFormatSource class in
    # cartridges/importer/source.py.
    class ExecutableFormatSource < Source
      class << self
        attr_writer :executable_format

        def executable_format = inherited_attribute(:executable_format, nil)
      end

      def executable_format = self.class.executable_format

      def make_executable(**arguments) = format(executable_format, **arguments)
    end

    # URLExecutableSource starts its games through a custom URL scheme, handed
    # to whichever opener the platform provides.
    #
    # Ported from the URLExecutableSource class in
    # cartridges/importer/source.py.
    class URLExecutableSource < ExecutableFormatSource
      OPENERS = {
        "win32" => "start",
        "linux" => "xdg-open",
        "darwin" => "open",
      }.freeze

      class << self
        attr_writer :url_format

        def url_format = inherited_attribute(:url_format, nil)
      end

      def url_format = self.class.url_format

      def executable_format
        OPENERS.fetch(Shared.platform) { raise NotImplementedError, "No URL handler for #{Shared.platform}" }
               .then { |opener| "#{opener} #{url_format}" }
      end
    end
  end
end
