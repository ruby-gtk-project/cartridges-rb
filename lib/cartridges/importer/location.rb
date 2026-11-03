# frozen_string_literal: true

require "pathname"
require_relative "../shared"
require_relative "../logging/setup"

module Cartridges
  module Importer
    # UnresolvableLocationError is raised when none of a location's candidate
    # roots has the files it needs. An optional location raising it is not
    # fatal to the import.
    #
    # Ported from cartridges/importer/location.py.
    class UnresolvableLocationError < StandardError
      attr_reader :optional

      def initialize(optional: false)
        @optional = optional
        super("No valid candidate for location")
      end
    end

    # LocationSubPath is one path a location must contain, and whether it is a
    # directory rather than a file.
    LocationSubPath = Data.define(:segment, :is_directory) do
      def self.file(segment) = new(segment: segment, is_directory: false)
      def self.directory(segment) = new(segment: segment, is_directory: true)
      def directory? = is_directory
    end

    # Location is a filesystem location with several candidate roots. The path
    # stored in the schema is always tried first; a candidate only counts when
    # every one of the location's subpaths exists under it; and the schema is
    # updated with whichever one was picked.
    #
    # Ported from cartridges/importer/location.py. The three invalid_subtitle
    # strings the preferences dialog shows under a mis-set location row live
    # here, as they do upstream.
    class Location
      # The variable is the name of the source.
      CACHE_INVALID_SUBTITLE = "Select the {} cache directory."
      # The variable is the name of the source.
      CONFIG_INVALID_SUBTITLE = "Select the {} configuration directory."
      # The variable is the name of the source.
      DATA_INVALID_SUBTITLE = "Select the {} data directory."

      attr_reader :schema_key, :candidates, :paths, :invalid_subtitle, :optional, :root

      def initialize(schema_key:, candidates:, paths:, invalid_subtitle:, optional: false)
        @schema_key = schema_key
        @candidates = candidates.to_a
        @paths = paths
        @invalid_subtitle = invalid_subtitle
        @optional = optional
        @root = nil
      end

      # Whether a candidate root carries every file and directory the location
      # declares.
      def check_candidate(candidate)
        @paths.each_value.all? do |subpath|
          (Pathname.new(candidate) / subpath.segment).then do |path|
            subpath.directory? ? path.directory? : path.file?
          end
        end
      end

      # Picks a root from the candidates, writes it back to the schema, and
      # raises when nothing fits.
      def resolve
        unless @root
          pick.then do |candidate|
            unless candidate
              raise UnresolvableLocationError.new(optional: @optional)
            end

            @root = candidate
            Shared.schema.set_string(@schema_key, candidate.to_s)
            Logging.logger.debug("Resolved value for schema key #{@schema_key}: #{candidate}")
          end
        end
        @root
      end

      # The computed path for one of the location's keys. An optional location
      # that cannot be resolved yields nil rather than raising.
      def [](key)
        resolved_root.then do |root|
          if root
            root / @paths.fetch(key).segment
          end
        end
      end

      private

        def resolved_root
          resolve
        rescue UnresolvableLocationError => e
          if e.optional
            nil
          else
            raise
          end
        end

        # The schema's value first, then the built-in candidates.
        def pick
          [Shared.schema.get_string(@schema_key), *@candidates]
            .map { |candidate| Pathname.new(candidate.to_s).expand_path }
            .find { |candidate| check_candidate(candidate) }
        end
    end
  end
end
