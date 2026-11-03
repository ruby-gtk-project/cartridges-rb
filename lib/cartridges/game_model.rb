# frozen_string_literal: true

require "adwaita"
require "json"
require "shellwords"
require_relative "shared"
require_relative "run_executable"

module Cartridges
  # GameModel is the game record: the fields the importers fill in, the ones
  # the JSON files on disk carry, and the two signals the store's managers hang
  # off ("update-ready" when the UI should redraw the game, "save-ready" when
  # the file manager should write it out).
  #
  # Ported from cartridges/game.py, which is one class doing two jobs: the
  # record and the library tile widget. This is the record half; the tile is
  # lib/cartridges/game.rb.
  class GameModel < GLib::Object
    type_register

    define_signal("update-ready", GLib::Signal::RUN_FIRST, nil, nil, Object)
    define_signal("save-ready", GLib::Signal::RUN_FIRST, nil, nil, Object)

    # The attributes the file manager persists, in the order upstream's
    # FileManager lists them.
    PERSISTED = %w[
      added
      executable
      game_id
      source
      hidden
      last_played
      name
      developer
      removed
      blacklisted
      version
    ].freeze

    attr_accessor :added, :executable, :game_id, :source, :hidden, :last_played,
                  :name, :developer, :removed, :blacklisted, :version, :loading, :filtered

    def initialize(data = {})
      super()
      @hidden = false
      @last_played = 0
      @developer = nil
      @removed = false
      @blacklisted = false
      @loading = 0
      @filtered = false
      @version = Shared::SPEC_VERSION
      update_values(data)
    end

    # Applies a hash of field values, converting an executable given as an
    # argument list into the single shell string the rest of the app uses.
    def update_values(data)
      data.each do |key, value|
        setter = :"#{key}="
        if respond_to?(setter)
          public_send(setter, key.to_s == "executable" ? joined_executable(value) : value)
        end
      end
      self
    end

    # The source a game is grouped under in the sidebar: "lutris_steam" games
    # belong to "lutris".
    def base_source = @source.to_s.split("_").first

    def hidden? = @hidden == true
    def removed? = @removed == true
    def blacklisted? = @blacklisted == true
    def filtered? = @filtered == true
    def loading? = @loading.to_i.positive?

    # Emits the signal the display manager listens for.
    def update = signal_emit("update-ready", {})

    # Emits the signal the file manager listens for.
    def save = signal_emit("save-ready", {})

    # The cover on disk, animated first, then still, then nothing.
    def cover_path
      [Shared::COVERS_DIR / "#{@game_id}.gif", Shared::COVERS_DIR / "#{@game_id}.tiff"]
        .find { |path| path.file? }
    end

    # Records the launch time, persists it, redraws, then starts the game and
    # optionally quits the app.
    def launch
      @last_played = Time.now.to_i
      save
      update
      RunExecutable.call(@executable)
      Shared.schema.get_boolean("exit-after-launch")
    end

    # Flips the hidden flag and persists it. The window pops the details page
    # and raises the undo toast around this call.
    def toggle_hidden
      @hidden = !hidden?
      save
      update
      hidden?
    end

    # Marks the game removed so the next startup deletes its files, and
    # persists that. The window raises the undo toast around this call.
    def remove_game
      @removed = true
      save
      update
    end

    # Adds or subtracts from the loading counter the spinner watches.
    def set_loading(state)
      @loading = @loading.to_i + state
      loading?
    end

    # The JSON body upstream's FileManager writes, sorted by key.
    def to_h = PERSISTED.sort.to_h { |attr| [attr, public_send(attr)] }

    def self.from_h(data) = new(data)

    # Reads a game back from the JSON file the file manager wrote.
    def self.from_file(path)
      JSON.parse(File.read(path)).then { |data| new(data) }
    end

    def to_s = "#<Cartridges::GameModel game_id=#{@game_id.inspect} name=#{@name.inspect}>"
    def inspect = to_s

    # Default handlers for the two signals. GLib's Ruby bindings look for a
    # signal_do_<name> method when a signal is emitted, so each defined signal
    # needs one even when nothing happens by default.
    def signal_do_update_ready(_additional_data) = nil
    def signal_do_save_ready(_additional_data) = nil

    private

      def joined_executable(value)
        value.is_a?(Array) ? Shellwords.join(value.map(&:to_s)) : value
      end
  end
end
