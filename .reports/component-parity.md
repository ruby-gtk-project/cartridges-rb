# Component parity — cartridges-rb

| | |
|---|---|
| Upstream | `origin/main` @ `c4454fd` |
| Port | `ruby` @ `6e281e9` |
| Units with full parity | most windows/dialogs, and now all seven import sources; **1 whole feature (search provider) still has no unit at all, and 1 shipped file (style.css) is dead** |

## Gap 1 — Lutris and itch import sources: closed this round, but unverified by any committed check

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

## Gap 3 — Search provider: entire upstream unit missing (unchanged)

Upstream ships a GNOME Shell search-provider integration as a separate
process: `search-provider/cartridges-search-provider.in` (the executable),
`search-provider/page.kramo.Cartridges.SearchProvider.ini` (the Shell
registration) and `.service.in` (the D-Bus activation unit). This lets a
user search for a game from GNOME Shell's overview without opening
Cartridges.

The port has:
- no file under any `search_provider`/`shell_search` name (`find` and
  `grep -rn SearchProvider` across the whole tree return nothing),
- no second executable alongside `exe/cartridges`,
- no D-Bus service registration anywhere in the gemspec or packaging files.

**Verdict: gap.** This is a whole upstream-visible feature (a GNOME Shell
search integration) with zero port presence — not a widget inside an
existing window, so no single `lib/*.rb` file's parity table will ever
surface it; it has to be tracked as its own unit, and right now it is
tracked nowhere.

## What does have parity

Spot-checked against the `test/drive_cartridges.rb` driver (141/141 checks
passing — see `test-parity.md` for the run) and by reading the files
directly:

- Main window, library tiles (play/menu revealers, filter/search/sort state),
  the primary menu, the Add/Edit game dialog (validation on empty
  name/executable), the details page, the About dialog (name, icon, version,
  developer, licence), the shortcuts dialog (every accelerator the driver
  checks resolves to the same key upstream binds), and the import
  progress/error/summary-toast flow for the six sources that *are* wired —
  all drive clean and match the behaviour the upstream source describes.
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

## Rules check

- No parity claim in this report rests on the scan or on reading code alone
  for the parts that could be driven: the 141-check driver run backs every
  "does have parity" claim above (see `test-parity.md` for the actual
  transcript).
- All three gaps above are named with file and line, not "probably missing
  somewhere," and Gap 1 is stated as what it now is — implemented but
  unverified by a committed check — rather than left reading as closed.
- None of the three gaps is excused by any comment in the source — see
  `accountability-ensurance.md`.
