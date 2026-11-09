# frozen_string_literal: true

# The part of Cartridges that loads without a display.
#
# This file exists because `require "gtk4"` initialises GTK at require time
# and raises Gtk::InitError when there is no display server, so anything that
# reaches a widget class cannot be loaded by a plain `ruby -e` or by a test
# process on a headless machine. The split is along that line and no other:
#
#   require "cartridges/rb"   the game record, the store, the importer
#                             sources and the other backend modules — no
#                             widget classes, loadable anywhere;
#   require "cartridges"      all of the above plus every widget and the
#                             application, which needs a display.
#
# It is also the file the gem's version constant lives under, which is why
# spec/spec_helper.rb requires it: the specs for the display-free half need
# nothing more, and the ones that drive widgets ask for "cartridges"
# themselves.
require_relative "relative_date"
require_relative "sqlite"
require_relative "store"
require_relative "importer/importer"
require_relative "importer/steam_source"
require_relative "importer/flatpak_source"
require_relative "importer/bottles_source"
require_relative "importer/legendary_source"
require_relative "importer/desktop_source"
require_relative "importer/retroarch_source"
require_relative "importer/heroic_source"
require_relative "importer/lutris_source"
require_relative "importer/itch_source"
require_relative "rb/version"
