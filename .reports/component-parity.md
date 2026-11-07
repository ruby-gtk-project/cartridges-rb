# Component parity — cartridges-rb

| | |
|---|---|
| Upstream | `origin/main` @ `c4454fd` |
| Port | `ruby` @ `fb67b2f` |
| Units with full parity | most windows/dialogs that exist; **3 import sources and 1 whole feature (search provider) have no unit at all** |

## Gap 1 — Lutris and itch import sources: built in the UI, dead in practice (Heroic closed this round)

**Update, this round:** `Importer::HeroicSource` is now ported
(`lib/cartridges/importer/heroic_source.rb`, wired into
`lib/cartridges/application.rb`'s `on_import_action` hash) — all four
sub-sources (sideload, Legendary/Epic, GOG, Nile/Amazon), each gated by its
own `heroic-import-*` key, each verified against fixture `library.json`/
`installed.json` files in a live Ruby session (sideload entry, an installed
Epic game, an entry filtered out for being not-installed, GOG, Amazon, and
the hidden-app-name filter from `store/config.json`, all producing the
right `GameModel` and `local_image_path`). It is pure JSON; nothing in it
needed a database driver.

Lutris and itch remain unported. I did not port them, and the reason is not
a design decision: `cartridges/importer/lutris_source.py` and
`cartridges/importer/itch_source.py` both read a SQLite database
(`pga.db`, `butler.db`) through `sqlite3.connect`, and no `sqlite3` gem is
resolvable in this fork's dev shell — `nix develop --command ruby -e
"require 'sqlite3'"` raises `LoadError: cannot load such file -- sqlite3`
in this session, confirmed live, with no local copy to vendor and no way
for this session to add one to `flake.nix`'s Ruby derivation without
rebuilding the fork's Nix inputs, which is out of scope for a single
import-source port. This is a real blocker, not an excuse to stop
looking — a future round should either get `sqlite3` into the flake's Ruby
gem set or shell out to the system `sqlite3` CLI to dump the two tables as
text, which would avoid the gem entirely.

**This remains a behavioural gap for these two, not just a missing file.**
The preferences dialog and GSettings schema still represent Lutris and itch
as live, switchable features; the import engine silently ignores both.

- `data/page.kramo.Cartridges.gschema.xml.in` (upstream) declares `lutris`,
  `lutris-location`, `lutris-cache-location`, `lutris-import-steam`,
  `lutris-import-flatpak`, `heroic`, `heroic-location`,
  `heroic-import-{epic,gog,amazon,sideload}`, `itch`, `itch-location` — 12
  keys, carried into the port's copy of the schema (`lib/cartridges/settings.rb`
  loads the same XML; the keys exist).
- `lib/cartridges/preferences_dialog.rb:16-23` lists `"lutris" => "Lutris"`,
  `"heroic" => "Heroic"`, `"itch" => "itch"` in `SOURCES`, and line 60
  (`SOURCES.each { |key, label| sources_group.add(bind_switch_row(...)) }`)
  builds a real, bound `Adw::SwitchRow` for each — toggling it writes
  `true`/`false` into the schema, same as Steam's row.
- `lib/cartridges/application.rb`'s `on_import_action` is the only place
  sources are ever instantiated and run. As of this round its hash now
  includes `"heroic" => Importer::HeroicSource`, but `lutris` and `itch`
  are still absent. There is no `Importer::LutrisSource` or
  `Importer::ItchSource` class anywhere in `lib/` (see the sqlite3 gem
  gap, above).

**Effect on a user:** flipping the Lutris/itch switch in Preferences →
General still looks identical to flipping the Steam switch (same row, same
binding, same persisted `true`), but `Ctrl+I` / `app.import` never looks at
those two keys and never scans those launchers. No error, no "not
supported" notice — the games are just never imported. This is exactly the
"a switch that does nothing" shape `component-parity`'s axis table warns
about, except it is worse than inert styling: it's an inert *action*. The
Heroic switch, as of this round, is no longer in this state.

**Verdict: gap, narrowed.** `HeroicSource` now has a full port counterpart.
`LutrisSource` and `ItchSource` do not, and the UI that should drive them
is still live and misleading.

## Gap 2 — Search provider: entire upstream unit missing

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

Spot-checked against the `test/drive_cartridges.rb` driver (139/139 checks
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
  for the parts that could be driven: the 139-check driver run backs every
  "does have parity" claim above (see `test-parity.md` for the actual
  transcript).
- The two gaps above are named with file and line, not "probably missing
  somewhere."
- Neither gap is excused by any comment in the source — see
  `accountability-ensurance.md`.
