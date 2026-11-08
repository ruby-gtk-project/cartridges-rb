# Component parity — cartridges-rb

| | |
|---|---|
| Upstream | `origin/main` @ `c4454fd` |
| Port | `ruby` @ `2cb65fe` |
| Units with full parity | most windows/dialogs, all seven import sources (with committed, driven coverage for Lutris/itch/Heroic), `style.css` now wired, and the search provider now discoverable/activatable on a real install with committed D-Bus coverage; **the one remaining component gap is the search provider's dropped cover art, and every component in the app still fails the text axis (see translation-parity.md)** |

## Gap 1 — Lutris and itch import sources: closed as of this round

**Update, this round:** the previous round's gap here — "implemented, not
verified" — is now closed. `test/drive_cartridges.rb` creates real
`pga.db`/`butler.db` fixtures and the import step asserts the actual
`GameModel`s produced (name, `source`, `game_id` round-trip exactly as the
Lutris/itch field mapping says they should; see `test-parity.md`'s addendum
for the transcript). This also surfaced and fixed a real concurrency bug in
`AsyncManager#process_game` (completion callback delivered off the GTK main
thread), which only a real end-to-end import could have found. **Verdict:
implemented and verified by a committed, repeatable check, for Lutris and
itch.** Heroic is not included in this close: it still gets only a presence
check (`d.check("Heroic was added as an import source...")`), never a
fixture import, so Heroic's four sub-sources (Epic/GOG/Amazon/sideload)
remain "implemented, not verified" exactly as this gap originally found. The
paragraphs below are kept as the historical record of the gap that preceded
this.

**Update, this round:** the `sqlite3` gem gap the previous round of this
report blocked on is resolved — `nix develop --command ruby -e "require
'sqlite3'"` now succeeds (`SQLite3::VERSION` → `2.10.2`), and both
`Importer::LutrisSource` (`lib/cartridges/importer/lutris_source.rb`) and
`Importer::ItchSource` (`lib/cartridges/importer/itch_source.rb`) are
ported, required from `lib/cartridges/application.rb` and wired into its
`on_import_action` source hash alongside `heroic`, `steam`, `flatpak`,
`bottles`, `legendary`, `desktop` and `retroarch`:

```ruby
# lib/cartridges/application.rb
"heroic" => Importer::HeroicSource,
"lutris" => Importer::LutrisSource,
"itch" => Importer::ItchSource,
```

Reading `itch_source.rb` against upstream's `itch_source.py` line by line,
the port is faithful: the same `caves`/`games` join query, the same
`still_cover_url || cover_url` fallback, the same `game_id_format`/
`make_executable` call shape. `lutris_source.rb` against
`lutris_source.py` is the same shape with the Steam/Flatpak-runner
exclusion flags reproduced as bound schema keys
(`lutris-import-steam`/`lutris-import-flatpak`).

I verified both live this round with a throwaway fixture — a synthetic
`pga.db` under a temp `XDG_DATA_HOME/lutris/`, loaded through `require
"cartridges"` under `xvfb-run` — and `LutrisSource.new.to_a` correctly
produced a `GameModel` (`name=My Game source=lutris_wine
game_id=lutris_wine_1 exe=xdg-open lutris:rungameid/1`) from a one-row
fixture database. **That verification is not in the repository.** It is
not a spec, not a driver check — it is a paragraph in this report. See
`test-parity.md` for the fuller accounting: `test/drive_cartridges.rb`
instantiates all three newest sources (its own log shows `Source lutris
skipped, bad location` and `Source itch skipped, bad location` next to
Heroic's identical line) but, because the sandbox has none of their real
launcher directories, never feeds any of the three real data and asserts
nothing about the games they would produce. Only Heroic gets even a
presence check (`d.check("Heroic was added as an import source...")`).

**Effect on a user:** flipping the Lutris/Heroic/itch switches in
Preferences → General is, as of this round, no longer misleading — all
three now do something real when `Ctrl+I` runs. But none of the three has
a regression check anywhere in the port's own test surface, so the next
change to any of them (a schema rename, a column reorder) ships with
nothing to catch it.

**Verdict: implemented, not verified.** The prior round's gap (dead
switches) is closed. A new, narrower gap replaces it: per the task's own
framing, "a component no check exercises is unverified, not done," and
that is the honest status of all three newest sources — Lutris and itch
with zero committed coverage of any kind, Heroic with one presence check
that never imports anything through it.

## Gap 2 — `lib/cartridges/style.css` is shipped and dead

`lib/cartridges/style.css` exists in the port (carried over from upstream's
`data/gtk/style.css`: the purple accent-color overrides for light and dark,
`.no-hover > flowboxchild:hover`, `#details_view`,
`#details_view_play_button`) but no file in `lib/` or `exe/` loads it —
`grep -rn "style.css\|CssProvider" lib/ exe/` returns nothing, re-confirmed
this round. Upstream's `main.py` registers this stylesheet with
`Gtk.CssProvider` at startup; the port never instantiates a
`Gtk::CssProvider` at all. The effect is invisible in a screenshot diff
(the app still renders, just with GTK's stock Adwaita accent instead of
upstream's purple, and without the two `#details_view` rules) and so is
exactly the kind of gap a driver script checking structure and bindings,
not pixel color, will never catch.

**Verdict: gap.** A shipped, unwired file — carried over as dead weight,
not ported as behaviour.

## Gap 3 — Search provider: built, but unreachable in any real install, and dropped data

**Update, this round:** `lib/cartridges/shell_search_provider.rb` and
`exe/cartridges-search-provider` now exist and implement all five
`org.gnome.Shell.SearchProvider2` methods (`GetInitialResultSet`,
`GetSubsearchResultSet`, `GetResultMetas`, `ActivateResult`, `LaunchSearch`),
reading every `game_id.json` on disk and filtering hidden/blacklisted/removed
games the same way upstream does. The commit that added it (`Port the GNOME
Shell search provider`) verified `GetInitialResultSet`/`GetResultMetas`
against a real `dbus-run-session` bus with `gdbus`, including special
characters and hidden-game filtering, and that verification reads as
genuine, not asserted from memory.

Two real sub-gaps survive this close, both confirmed live this round:

1. **The feature cannot be discovered or activated in any real install.**
   Upstream ships three files for this unit, not one:
   `cartridges-search-provider.in` (the executable — ported),
   `page.kramo.Cartridges.SearchProvider.ini` (tells GNOME Shell this
   provider exists and which bus name/object path to call) and
   `page.kramo.Cartridges.SearchProvider.service.in` (tells `dbus-daemon`
   how to spawn the executable on demand when something calls that bus
   name). The port has neither of the last two: `find . -iname
   '*.service*' -o -iname '*SearchProvider*.ini'` under the port returns
   nothing, and `grep -rn 'search-providers\|dbus-1/services' cartridges-rb.gemspec
   Rakefile` returns nothing. Upstream's own `search-provider/meson.build`
   installs these two files to `$datadir/gnome-shell/search-providers/` and
   `$datadir/dbus-1/services/`; the port installs nothing to either path,
   anywhere. **A real user who installs this gem and opens GNOME Shell's
   overview gets no search results from Cartridges, ever** — the shell has
   no registration to read, and D-Bus has no activation record for
   `page.kramo.Cartridges.SearchProvider`, so nothing would ever launch
   `exe/cartridges-search-provider` on their machine. The live verification
   in the commit message worked only because `dbus-run-session` + manual
   `gdbus call` stand in for both of those missing mechanisms by hand.
2. **Cover art is dropped.** `GetResultMetas` omits the `icon-data`
   (`(iiibiiay)` raw pixel buffer) field upstream includes; `component-parity`'s
   text/behaviour axes are otherwise met (id/name/description), but a
   result's icon is part of this component's identity same as a button's
   `destructive-action` class is, and it is simply absent — confirmed by
   reading `result_meta` in `shell_search_provider.rb`, which builds only
   `id`, `name` and `description`.

**Verdict: gap, narrowed but not closed.** The code is real and the five
D-Bus methods behave correctly when called directly — but "behaves correctly
when called directly" is not the same claim as "is a feature a GNOME Shell
user has", and right now this port has code for a search provider and no way
for anything on a real desktop to ever reach it.

## What does have parity

Spot-checked against the `test/drive_cartridges.rb` driver (147/147 checks
passing — see `test-parity.md` for the run) and by reading the files
directly:

- Main window, library tiles (play/menu revealers, filter/search/sort state),
  the primary menu, the Add/Edit game dialog (validation on empty
  name/executable), the details page, the About dialog (name, icon, version,
  developer, licence), the shortcuts dialog (every accelerator the driver
  checks resolves to the same key upstream binds), and the import
  progress/error/summary-toast flow for all seven sources — all drive clean
  and match the behaviour the upstream source describes, with Lutris and
  itch now backed by real fixture-import assertions and Heroic still backed
  by only a presence check (see Gap 1).
- The preferences dialog's general switches, the SGDB group and the API-key
  row read/write through to the schema correctly.

These are real parity, not just "present" — the driver exercises the
behaviour (toggling a switch, round-tripping through `Gio::Settings`), which
is what this skill's Step 5 asks for.

## Text axis

Every widget in every file above builds its label as a bare Ruby string
literal, never through a translation call. This fails the text axis for
**every single component in the app**, not a subset — see
`translation-parity.md` for the full accounting; it is recorded here because
`component-parity` requires closing text-axis gaps against both ledgers.

## Round 5 update, re-audited at `2cb65fe`

One commit landed: `Wire style.css, search-provider data files, and
Heroic/shell-provider test coverage`. Re-checked each claim live rather
than from the commit title:

- **Gap 2 (`style.css` shipped and dead) — closed.** `grep -n "CssProvider"
  lib/cartridges/application.rb` now returns `load_css`, `css_provider`,
  `Gtk::CssProvider.new.tap { |provider| provider.load_from_path(...) }`
  and `Gtk::StyleContext.add_provider_for_display(...)`, called from the
  app's `startup` path. The purple accent overrides and the two
  `#details_view` rules now actually load. Verdict: **parity.**
- **Gap 3, sub-gap 1 (unreachable on a real install) — closed.**
  `data/page.kramo.Cartridges.SearchProvider.ini` and
  `data/page.kramo.Cartridges.SearchProvider.service.in` now exist,
  `cartridges-rb.gemspec`'s `executables` lists
  `cartridges-search-provider`, and `Rakefile`'s `install:search_provider`
  task installs the substituted `.ini`/`.service` to
  `$datadir/gnome-shell/search-providers/` and `$datadir/dbus-1/services/`
  — matching upstream's `search-provider/meson.build` install targets.
  Verdict: **parity** on discoverability/activation.
- **Gap 3's missing committed test — closed.**
  `test/drive_shell_search_provider.rb` now drives all five D-Bus methods
  against a real `dbus-run-session` bus. Re-ran it live this round:
  16/16 passed.
- **Gap 1's Heroic carve-out — closed.** `test/drive_cartridges.rb` now
  seeds real fixture files for all four Heroic sub-sources (sideload,
  Legendary/Epic, GOG, Nile/Amazon) and asserts each one's actual produced
  `GameModel` (name, source, id), not just that Heroic was registered.
  Re-ran the full driver live this round: 151/151 passed, plus the
  search-provider driver's 16/16 — 167 total, matching the task's own
  runtime gate exactly.

**Gap 3, sub-gap 2 (cover art / `icon-data` dropped from search results) —
still open, unchanged.** `lib/cartridges/shell_search_provider.rb:149`'s
`result_meta` still builds only `id`, `name` and `description`; re-grepped
`icon\|cover` against the file live this round and it still returns
nothing. This commit did not touch it, and neither does anything else on
this branch. A GNOME Shell search result for any game here still shows no
thumbnail, where upstream's does. **Verdict: gap, unchanged.**

**Translation (text axis) — still open, unchanged.** Every widget in every
file above still builds its labels as bare Ruby string literals; see
`translation-parity.md`.

## Rules check

- No parity claim in this report rests on the scan or on reading code alone
  for the parts that could be driven: the 151+16=167-check driver run (both
  scripts re-run live this round) backs every "does have parity" claim
  above (see `test-parity.md` for the transcript).
- The one remaining gap (cover art dropped from search results) is named
  with file and line, not "probably missing somewhere," and every gap this
  round's commit actually closed is stated as closed rather than left
  reading as still open, and vice versa.
- The remaining gap is not excused by any comment in the source — see
  `accountability-ensurance.md`.
