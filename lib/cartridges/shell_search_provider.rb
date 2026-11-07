# frozen_string_literal: true

require "gio2"
require "json"
require_relative "shared"

module Cartridges
  # ShellSearchProvider is the standalone D-Bus service behind
  # org.gnome.Shell.SearchProvider2: it loads every game_id.json on disk once
  # at startup, answers the shell's search queries against each game's name
  # (and developer, as the result's description), and hands activation back
  # to the `cartridges` executable's `--launch`/`--search` options so the
  # actual game runs in the main app, not in this service.
  #
  # Ported from the Server and SearchCartridgesService classes in
  # search-provider/cartridges-search-provider.in. Upstream's `Server` builds
  # its method signatures by introspecting its own docstring at runtime;
  # the Ruby D-Bus bindings' GVariant tuple/dict constructors from Ruby
  # values are unimplemented (`GLib::Variant.new` raises "TODO: Ruby ->
  # GVariant" for every compound type this interface returns), so the out
  # arguments below are built from GVariant's text format instead, with
  # every string value going through `to_json` for quoting and escaping.
  class ShellSearchProvider
    BUS_NAME = "org.gnome.Shell.SearchProvider2"
    OBJECT_PATH = "#{Shared::PREFIX}/SearchProvider"

    INTROSPECTION_XML = <<~XML
      <node>
        <interface name="org.gnome.Shell.SearchProvider2">
          <method name="GetInitialResultSet">
            <arg type="as" name="terms" direction="in" />
            <arg type="as" name="results" direction="out" />
          </method>
          <method name="GetSubsearchResultSet">
            <arg type="as" name="previous_results" direction="in" />
            <arg type="as" name="terms" direction="in" />
            <arg type="as" name="results" direction="out" />
          </method>
          <method name="GetResultMetas">
            <arg type="as" name="identifiers" direction="in" />
            <arg type="aa{sv}" name="metas" direction="out" />
          </method>
          <method name="ActivateResult">
            <arg type="s" name="identifier" direction="in" />
            <arg type="as" name="terms" direction="in" />
            <arg type="u" name="timestamp" direction="in" />
          </method>
          <method name="LaunchSearch">
            <arg type="as" name="terms" direction="in" />
            <arg type="u" name="timestamp" direction="in" />
          </method>
        </interface>
      </node>
    XML

    def initialize
      @games = load_games_from_disk
    end

    def run
      application.tap do |app|
        app.signal_connect("startup") do
          own_bus_name
          app.hold
        end
        app.run([])
      end
    end

    private

      # game_id => [name, developer]
      def load_games_from_disk
        return {} unless Shared::GAMES_DIR.directory?

        Shared::GAMES_DIR.each_child.each_with_object({}) do |path, games|
          next unless path.extname == ".json"

          add_game_from_file(path, games)
        end
      end

      def add_game_from_file(path, games)
        data = JSON.parse(File.read(path))
        return if data["hidden"] || data["blacklisted"] || data["removed"]

        games[data["game_id"]] = [data["name"], data["developer"]]
      rescue JSON::ParserError, SystemCallError, TypeError
        nil
      end

      def application
        @application ||= Gio::Application.new(
          "#{Shared::APP_ID}.SearchProvider",
          :is_service,
        ).tap { |app| app.inactivity_timeout = 10_000 }
      end

      def own_bus_name = Gio.bus_own_name_on_connection(connection, BUS_NAME, :none)

      def connection = @connection ||= Gio.bus_get_sync(:session, nil).tap { |conn| register_object(conn) }

      def register_object(connection)
        connection.register_object(OBJECT_PATH, interface_info) do |_connection, _sender, _object_path, _interface_name, method_name, parameters, invocation|
          dispatch(method_name, parameters, invocation)
        end
      end

      def interface_info = Gio::DBusNodeInfo.new(INTROSPECTION_XML).lookup_interface(BUS_NAME)

      def dispatch(method_name, parameters, invocation)
        case method_name
        when "GetInitialResultSet" then get_initial_result_set(parameters, invocation)
        when "GetSubsearchResultSet" then get_subsearch_result_set(parameters, invocation)
        when "GetResultMetas" then get_result_metas(parameters, invocation)
        when "ActivateResult" then activate_result(parameters, invocation)
        when "LaunchSearch" then launch_search(parameters, invocation)
        end
      rescue StandardError => e
        invocation.return_dbus_error("org.gnome.Shell.SearchProvider2.Error", e.message)
      end

      def get_initial_result_set(parameters, invocation)
        terms, = parameters
        invocation.return_value(variant_tuple(search(terms), "(as)"))
      end

      def get_subsearch_result_set(parameters, invocation)
        _previous_results, terms = parameters
        invocation.return_value(variant_tuple(search(terms), "(as)"))
      end

      # The game ids whose name or developer contains every search term,
      # the same substring match upstream's __search does.
      def search(terms)
        needle = terms.join(" ").downcase
        @games.select { |_game_id, (name, developer)| matches?(needle, name, developer) }.keys
      end

      def matches?(needle, name, developer)
        name.to_s.downcase.include?(needle) || developer.to_s.downcase.include?(needle)
      end

      def get_result_metas(parameters, invocation)
        game_ids, = parameters
        invocation.return_value(variant_tuple(game_ids.filter_map { |game_id| result_meta(game_id) }, "(aa{sv})"))
      end

      def result_meta(game_id)
        name, developer = @games[game_id]
        return nil unless name

        fields = ["'id': <#{game_id.to_json}>", "'name': <#{name.to_json}>"]
        fields << "'description': <#{developer.to_json}>" unless developer.to_s.empty?
        "{#{fields.join(", ")}}"
      end

      def activate_result(parameters, invocation)
        game_id, = parameters
        spawn_cartridges(["--launch", game_id])
        invocation.return_value(nil)
      end

      def launch_search(parameters, invocation)
        terms, = parameters
        spawn_cartridges(["--search", terms.join(" ")])
        invocation.return_value(nil)
      end

      def spawn_cartridges(args)
        Process.detach(Process.spawn("cartridges", *args))
      rescue Errno::ENOENT
        nil
      end

      # Builds a GVariant of a tuple type from GVariant's text format,
      # since the bindings' value-based tuple constructor is unimplemented.
      # `items` is either an array of already-quoted GVariant-text fragments
      # (dict entries, for `aa{sv}`) or plain strings (for `as`), so string
      # values must already have gone through `to_json` by the caller.
      def variant_tuple(items, type)
        inner = items.map { |item| item.is_a?(String) && item.start_with?("{") ? item : item.to_json }
        GLib::Variant.parse("(#{"[#{inner.join(", ")}]"},)", type)
      end
  end
end
