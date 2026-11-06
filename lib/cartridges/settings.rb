# frozen_string_literal: true

require "adwaita"

module Cartridges
  # Settings resolves the two GSettings schemas the app keeps its state in.
  #
  # Ported from upstream's data/page.kramo.Cartridges.gschema.xml.in, which
  # declares "page.kramo.Cartridges" with the 36 application keys and
  # "page.kramo.Cartridges.State" with the 6 window/session keys. That XML is
  # installed as data/schemas/page.kramo.Cartridges.gschema.xml in this port,
  # with meson's @APP_ID@ and @PREFIX@ substitutions already applied.
  #
  # GSettings reads a *compiled* schema directory, so running from a checkout
  # compiles data/schemas on demand; an installed copy found through
  # XDG_DATA_DIRS needs none of that.
  module Settings
    APP_ID = "page.kramo.Cartridges"
    STATE_SCHEMA_ID = "#{APP_ID}.State"

    SCHEMA_DIR = File.expand_path("../../data/schemas", __dir__)
    SCHEMA_XML = File.join(SCHEMA_DIR, "#{APP_ID}.gschema.xml")
    COMPILED = File.join(SCHEMA_DIR, "gschemas.compiled")

    class << self
      def schema = @schema ||= lookup(APP_ID)
      def state_schema = @state_schema ||= lookup(STATE_SCHEMA_ID)

      # A Gio::Settings for a schema id, preferring the repository's own
      # compiled schema directory and falling back to the installed default.
      def lookup(schema_id)
        compile_source_dir
        source&.lookup(schema_id, true).then do |found|
          if found
            Gio::Settings.new(schema: found)
          else
            Gio::Settings.new(schema_id)
          end
        end
      end

      # The repository's schema directory as a schema source, or nil when the
      # port runs from an installed tree that has no such directory.
      def source
        unless defined?(@source)
          @source = load_source
        end
        @source
      end

      # Compiles data/schemas when the XML is newer than the compiled cache,
      # which is what makes `ruby exe/cartridges` work in a fresh checkout.
      def compile_source_dir
        (File.exist?(SCHEMA_XML) && stale?).then do |needed|
          if needed
            system("glib-compile-schemas", SCHEMA_DIR, out: File::NULL, err: File::NULL)
          end
        end
      end

      def stale?
        !File.exist?(COMPILED) || File.mtime(SCHEMA_XML) > File.mtime(COMPILED)
      end

      private

        def load_source
          File.exist?(COMPILED).then do |compiled|
            if compiled
              Gio::SettingsSchemaSource.new(SCHEMA_DIR, Gio::SettingsSchemaSource.default, true)
            end
          end
        rescue GLib::Error => e
          warn "Could not load schema source #{SCHEMA_DIR}: #{e.message}"
          nil
        end
    end
  end
end
