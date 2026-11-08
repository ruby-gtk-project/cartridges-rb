# frozen_string_literal: true

# Drives Cartridges::ShellSearchProvider (lib/cartridges/shell_search_provider.rb)
# against a real D-Bus session bus: spawns the provider in a child process,
# waits for it to own org.gnome.Shell.SearchProvider2, then calls every
# org.gnome.Shell.SearchProvider2 method with `gdbus call` the way GNOME
# Shell itself would, and asserts the replies.
#
# This closes the gap the port commit left: the only prior verification was
# a one-off interactive gdbus session that is not in the repository and will
# not run again. This script is that session, scripted and repeatable.
#
# Run it from the repository root, inside a private D-Bus session bus (the
# provider owns a bus name, and doing that on the real session bus would
# collide with anything else the search-provider test leaves running):
#
#   nix develop --command xvfb-run -a dbus-run-session -- ruby test/drive_shell_search_provider.rb
#
# xvfb-run has to wrap dbus-run-session (not the other way around): this
# script's child process requires "adwaita", and the Ruby GTK4 bindings
# fail Gtk::InitError at require time with no display at all, even though
# this script never opens a window.

require "fileutils"
require "json"
require "open3"
require "tmpdir"

abort("DBUS_SESSION_BUS_ADDRESS is not set - run this under `dbus-run-session --`") if ENV["DBUS_SESSION_BUS_ADDRESS"].to_s.empty?

XDG_HOME = Dir.mktmpdir("cartridges-search-provider-drive")
ENV["XDG_CONFIG_HOME"] = File.join(XDG_HOME, "config")
ENV["XDG_DATA_HOME"] = File.join(XDG_HOME, "data")
ENV["XDG_CACHE_HOME"] = File.join(XDG_HOME, "cache")
FileUtils.mkdir_p(ENV.fetch("XDG_CONFIG_HOME"))
FileUtils.mkdir_p(ENV.fetch("XDG_DATA_HOME"))
FileUtils.mkdir_p(ENV.fetch("XDG_CACHE_HOME"))

GAMES_DIR = File.join(ENV.fetch("XDG_DATA_HOME"), "cartridges", "games")
FileUtils.mkdir_p(GAMES_DIR)

GAMES = {
  "chess" => {"game_id" => "chess", "name" => "Chess", "developer" => "kramo"},
  "zelda" => {"game_id" => "zelda", "name" => "The Legend of Zelda", "developer" => "Nintendo"},
  "no_developer" => {"game_id" => "no_developer", "name" => "Mystery Game", "developer" => ""},
  "hidden_game" => {"game_id" => "hidden_game", "name" => "Hidden Chess", "developer" => "kramo", "hidden" => true},
  "blacklisted_game" => {"game_id" => "blacklisted_game", "name" => "Blacklisted Chess", "developer" => "kramo", "blacklisted" => true},
  "removed_game" => {"game_id" => "removed_game", "name" => "Removed Chess", "developer" => "kramo", "removed" => true},
}.freeze

GAMES.each { |game_id, data| File.write(File.join(GAMES_DIR, "#{game_id}.json"), JSON.generate(data)) }

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))

N_CHECKS = {ok: 0, fail: 0}

def check(description)
  if yield
    N_CHECKS[:ok] += 1
    puts "  ok   #{description}"
  else
    N_CHECKS[:fail] += 1
    puts "  FAIL #{description}"
  end
rescue => e
  N_CHECKS[:fail] += 1
  puts "  FAIL #{description} (raised #{e.class}: #{e.message})"
end

def gdbus_call(method, args)
  out, err, status = Open3.capture3(
    "gdbus", "call", "--session",
    "--dest", "org.gnome.Shell.SearchProvider2",
    "--object-path", "/page/kramo/Cartridges/SearchProvider",
    "--method", "org.gnome.Shell.SearchProvider2.#{method}",
    *args,
  )
  raise "gdbus call #{method} failed: #{err}" unless status.success?

  out
end

provider_script = <<~RUBY
  $LOAD_PATH.unshift(#{File.expand_path("../lib", __dir__).inspect})
  require "cartridges/shell_search_provider"
  Cartridges::ShellSearchProvider.new.run
RUBY

provider_pid = Process.spawn({"XDG_CONFIG_HOME" => ENV.fetch("XDG_CONFIG_HOME"), "XDG_DATA_HOME" => ENV.fetch("XDG_DATA_HOME"), "XDG_CACHE_HOME" => ENV.fetch("XDG_CACHE_HOME")}, "ruby", "-e", provider_script)

begin
  # Poll for the provider to own its bus name instead of a fixed sleep.
  owned = false
  deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 20
  until owned || Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
    out, = Open3.capture3("gdbus", "call", "--session", "--dest", "org.freedesktop.DBus", "--object-path", "/org/freedesktop/DBus", "--method", "org.freedesktop.DBus.NameHasOwner", "org.gnome.Shell.SearchProvider2")
    owned = out.include?("true")
    sleep(0.1) unless owned
  end

  puts "[1] the provider owns org.gnome.Shell.SearchProvider2 on the session bus"
  check("the bus name was owned within the timeout") { owned }

  puts "[2] GetInitialResultSet matches by name, case-insensitively, and skips hidden/blacklisted/removed games"
  result = gdbus_call("GetInitialResultSet", ["['chess']"])
  check("it returns chess's game_id") { result.include?("'chess'") }
  check("it does not return the hidden game") { !result.include?("hidden_game") }
  check("it does not return the blacklisted game") { !result.include?("blacklisted_game") }
  check("it does not return the removed game") { !result.include?("removed_game") }

  result_upper = gdbus_call("GetInitialResultSet", ["['CHESS']"])
  check("the match is case-insensitive") { result_upper.include?("'chess'") }

  result_dev = gdbus_call("GetInitialResultSet", ["['nintendo']"])
  check("a search term matches the developer field too") { result_dev.include?("'zelda'") }

  result_hidden_term = gdbus_call("GetInitialResultSet", ["['Hidden Chess']"])
  check("searching the hidden game's own name still returns nothing (it was never loaded)") { !result_hidden_term.include?("hidden_game") }

  puts "[3] GetSubsearchResultSet behaves like GetInitialResultSet on the new terms"
  result_sub = gdbus_call("GetSubsearchResultSet", ["['chess']", "['zelda']"])
  check("it returns zelda's game_id for the new terms") { result_sub.include?("'zelda'") }

  puts "[4] GetResultMetas returns id/name/description for loaded games and omits unknown ids"
  metas = gdbus_call("GetResultMetas", ["['chess', 'zelda', 'no_developer', 'does_not_exist']"])
  check("chess's meta carries its id and name") { metas.include?("'id': <'chess'>") && metas.include?("'name': <'Chess'>") }
  check("chess's meta carries its developer as the description") { metas.include?("'description': <'kramo'>") }
  check("zelda's meta carries its developer as the description") { metas.include?("'description': <'Nintendo'>") }
  check("a game with an empty developer has no description field") { !metas.scan(/\{[^}]*'id': <'no_developer'>[^}]*\}/).first.to_s.include?("description") }
  check("an unknown id produces no entry at all") { metas.scan("'id':").length == 3 }

  puts "[5] ActivateResult and LaunchSearch accept the call and return empty (no `cartridges` binary on PATH here)"
  check("ActivateResult returns successfully") { gdbus_call("ActivateResult", ["'chess'", "['chess']", "0"]) == "()\n" }
  check("LaunchSearch returns successfully") { gdbus_call("LaunchSearch", ["['chess']", "0"]) == "()\n" }
ensure
  Process.kill("TERM", provider_pid)
  Process.wait(provider_pid)
end

puts
puts "#{N_CHECKS[:ok]} of #{N_CHECKS[:ok] + N_CHECKS[:fail]} checks passed"
if N_CHECKS[:fail].zero?
  puts "DRIVE OK"
else
  abort("DRIVE FAILED")
end
