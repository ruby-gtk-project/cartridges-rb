# Component parity — cartridges-rb

| | |
|---|---|
| Upstream | `origin/main` @ `c4454fd` |
| Port | `ruby` @ `fb67b2f` |
| Units with full parity | most windows/dialogs that exist; **3 import sources and 1 whole feature (search provider) have no unit at all** |

## Gap 1 — Lutris, Heroic and itch import sources: built in the UI, dead in practice

**This is a behavioural gap, not just a missing file.** The preferences
dialog and GSettings schema both represent these three sources as live,
switchable features; the import engine silently ignores all three.

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
- `lib/cartridges/application.rb:218-230` (`on_import_action`) is the only
  place sources are ever instantiated and run. Its hash is:
  ```ruby
  {
    "steam" => Importer::SteamSource,
    "flatpak" => Importer::FlatpakSource,
    "bottles" => Importer::BottlesSource,
    "legendary" => Importer::LegendarySource,
    "desktop" => Importer::DesktopSource,
    "retroarch" => Importer::RetroarchSource,
  }.each { |key, klass| Shared.importer.add_source(klass.new) if Shared.schema.get_boolean(key) }
  ```
  `lutris`, `heroic` and `itch` are absent from this hash. There is no
  `Importer::LutrisSource`, `Importer::HeroicSource` or `Importer::ItchSource`
  class anywhere in `lib/` (confirmed in `component-identification.md`).

**Effect on a user:** flipping the Lutris/Heroic/itch switch in Preferences
→ General looks identical to flipping the Steam switch (same row, same
binding, same persisted `true`), but `Ctrl+I` / `app.import` never looks at
those three keys and never scans those launchers. No error, no "not
supported" notice — the games are just never imported. This is exactly the
"a switch that does nothing" shape `component-parity`'s axis table warns
about, except it is worse than inert styling: it's an inert *action*.

**Verdict: gap.** Three upstream components (`LutrisSource`, `HeroicSource`,
`ItchSource`, each with their own location-resolution and multi-sub-source
logic — Heroic alone covers Epic/GOG/Amazon/sideload) have no port
counterpart, and the UI that should drive them is live and misleading.

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
