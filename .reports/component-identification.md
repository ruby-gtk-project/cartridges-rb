# Component identification — cartridges-rb

| | |
|---|---|
| Upstream | `origin/main` @ `c4454fd` |
| Port | `ruby` @ `2cb65fe` |

This supersedes nothing in `.reports/component-inventory.md` (the pre-build
planning inventory); it re-identifies both trees as they stand now, after the
port landed, to feed `component-parity`. It also supersedes the prior round
of this report (written at `6e281e9`), which found the search provider
entirely unported and Lutris/itch untested; two commits landed since
(`Port the GNOME Shell search provider`, `Drive real Lutris/itch imports;
fix async manager main-thread race`) and are re-checked below.

## Upstream file inventory (declarative + source)

Declarative UI (`data/gtk/*.blp`) — five template roots, each the unit list
for one port file:

| `.blp` | Root | Backing `.py` |
|---|---|---|
| `window.blp` | `CartridgesWindow : Adw.ApplicationWindow` | `window.py` |
| `game.blp` | `CartridgesGame : Gtk.FlowBoxChild` (library tile) | `game.py` |
| `details-dialog.blp` | `CartridgesDetailsDialog : Adw.Dialog` | `details_dialog.py` |
| `preferences.blp` | `CartridgesPreferencesDialog : Adw.PreferencesDialog` | `preferences.py` |
| `shortcuts-dialog.blp` | `CartridgesShortcutsDialog : Adw.ShortcutsDialog` | (none — pure `.blp`) |

Source files, one row per upstream module, with the port file it maps to and
whether that file exists:

| Upstream | Port | Exists? |
|---|---|---|
| `cartridges/main.py` | `lib/cartridges/application.rb` | yes |
| `cartridges/window.py` | `lib/cartridges/window.rb` (+ `window_menus.rb`, `source_row.rb`, `hidden_library_page.rb`, `library_notices.rb` — factored) | yes |
| `cartridges/game.py` | `lib/cartridges/game.rb` (+ `game_model.rb`, `game_cover.rb`, `game_menus.rb` — factored) | yes |
| `cartridges/details_dialog.py` | `lib/cartridges/details_dialog.rb` (+ `details_page.rb`) | yes |
| `cartridges/preferences.py` | `lib/cartridges/preferences_dialog.rb` | yes |
| `cartridges/shared.py.in` / `shared.pyi` | `lib/cartridges/shared.rb` + `lib/cartridges/settings.rb` | yes |
| `cartridges/errors/error_producer.py` | `lib/cartridges/error_producer.rb` | yes |
| `cartridges/errors/friendly_error.py` | `lib/cartridges/friendly_error.rb` | yes |
| `cartridges/utils/create_dialog.py` | `lib/cartridges/create_dialog.rb` | yes |
| `cartridges/utils/rate_limiter.py` | `lib/cartridges/rate_limiter.rb` | yes |
| `cartridges/utils/relative_date.py` | `lib/cartridges/relative_date.rb` | yes |
| `cartridges/utils/run_executable.py` | `lib/cartridges/run_executable.rb` | yes |
| `cartridges/utils/save_cover.py` | `lib/cartridges/save_cover.rb` | yes |
| `cartridges/utils/sqlite.py` | `lib/cartridges/sqlite.rb` | yes |
| `cartridges/utils/steamgriddb.py` | `lib/cartridges/steamgriddb.rb` | yes |
| `cartridges/utils/steam.py` | `lib/cartridges/steam.rb` | yes |
| `cartridges/logging/*.py` (3 files) | `lib/cartridges/logging/*.rb` (3 files) | yes |
| `cartridges/store/store.py` | `lib/cartridges/store.rb` | yes |
| `cartridges/store/pipeline.py` | `lib/cartridges/store/pipeline.rb` | yes |
| `cartridges/store/managers/*.py` (7 files) | `lib/cartridges/store/managers/*.rb` (7 files) | yes |
| `cartridges/importer/importer.py` | `lib/cartridges/importer/importer.rb` | yes |
| `cartridges/importer/source.py` | `lib/cartridges/importer/source.rb` | yes |
| `cartridges/importer/location.py` | `lib/cartridges/importer/location.rb` | yes |
| `cartridges/importer/steam_source.py` | `lib/cartridges/importer/steam_source.rb` | yes |
| `cartridges/importer/flatpak_source.py` | `lib/cartridges/importer/flatpak_source.rb` | yes |
| `cartridges/importer/bottles_source.py` | `lib/cartridges/importer/bottles_source.rb` | yes |
| `cartridges/importer/legendary_source.py` | `lib/cartridges/importer/legendary_source.rb` | yes |
| `cartridges/importer/desktop_source.py` | `lib/cartridges/importer/desktop_source.rb` | yes |
| `cartridges/importer/retroarch_source.py` | `lib/cartridges/importer/retroarch_source.rb` | yes |
| `cartridges/importer/lutris_source.py` | `lib/cartridges/importer/lutris_source.rb` | yes (new this round) |
| `cartridges/importer/heroic_source.py` | `lib/cartridges/importer/heroic_source.rb` | yes (landed previous round) |
| `cartridges/importer/itch_source.py` | `lib/cartridges/importer/itch_source.rb` | yes (new this round) |
| `data/gtk/shortcuts-dialog.blp` | `lib/cartridges/shortcuts_dialog.rb` | yes |
| `po/` (38 locales, `cartridges.pot`, `LINGUAS`, `POTFILES`) | — | **no `po/` anywhere in the port** |
| `search-provider/cartridges-search-provider.in` | `lib/cartridges/shell_search_provider.rb` + `exe/cartridges-search-provider` | yes (new this round) |
| `search-provider/page.kramo.Cartridges.SearchProvider.ini` | — | **missing — no `data/` file, and nothing installs one** |
| `search-provider/page.kramo.Cartridges.SearchProvider.service.in` | — | **missing — no `data/` file, and nothing installs one** |
| `search-provider/meson.build` (installs the two files above to `$datadir/gnome-shell/search-providers/` and `$datadir/dbus-1/services/`) | — | **no correspondence — the gemspec/Rakefile install nothing under either path** |

Everything else upstream ships (`build-aux/`, `meson.build`, `data/icons/`,
`.github/`) is packaging/build plumbing with a Ruby/`kettle-jem`
correspondence already in place (`Gemfile`, `flake.nix`, `exe/cartridges`,
`Rakefile`) and is not re-identified here as a UI component.

## Port's own extra/factored files

All of `game_model.rb`, `game_cover.rb`, `game_menus.rb`, `window_menus.rb`,
`source_row.rb`, `hidden_library_page.rb`, `library_notices.rb`,
`details_page.rb`, `http_client.rb` are explained — each carries a "Ported
from" comment naming the upstream file it was factored out of (verified by
reading each file's header). None is an unexplained extra.

## What `component-parity` and `translation-parity` take from this

- All three importer sources (Lutris, Heroic, itch) now have a port file,
  are required from `lib/cartridges/application.rb`, and are wired into
  `Preferences`'s `SOURCES` hash exactly like Steam/Flatpak/Bottles. Reading
  each file confirms it carries the same query/field logic as its upstream
  `.py` (verified line-by-line for `itch_source.rb` against
  `itch_source.py`; see `component-parity.md`). **Existing in `lib/` is not
  the same claim as "exercised by a check"** — see `test-parity.md` for why
  none of the three has a committed, repeatable test, only this round's ad
  hoc verification.
- The search-provider executable and its D-Bus interface are now built
  (`lib/cartridges/shell_search_provider.rb`, `exe/cartridges-search-provider`)
  and were driven live against a real session bus this round (see
  `component-parity.md`). **But the other two upstream files in that unit —
  `page.kramo.Cartridges.SearchProvider.ini` (the GNOME Shell registration)
  and `.service.in` (the D-Bus activation unit) — have no port counterpart at
  all, and nothing in the gemspec, `Rakefile` or `data/` installs anything to
  `$datadir/gnome-shell/search-providers/` or `$datadir/dbus-1/services/`.**
  Re-confirmed this round: `find . -iname '*.service*' -o -iname
  '*searchprovider*.ini'` under the port returns nothing outside `.git`. GNOME
  Shell has no mechanism to discover this provider, and D-Bus has no
  activation record for its bus name, in any real install of this gem — the
  executable only runs because a developer invokes it by hand or `dbus-run-session`
  stands in for the session bus directly, as the commit's own verification did.
  Four upstream files map to this unit; two have a port file and two do not.
- There is still no `po/` directory and (confirmed by grep, see
  `translation-parity.md`) no gettext call anywhere in `lib/`. Unchanged
  from the prior round.
- `lib/cartridges/style.css` (flagged in `component-inventory.md` as
  present but unwired) is still never referenced by any `Gtk::CssProvider`
  call anywhere in `lib/` or `exe/` (re-confirmed this round by grep) — a
  shipped file with dead CSS, not a missing one, so it does not show up as
  an absent port file but is a real behavioural gap (the purple accent
  overrides and `#details_view` rules it defines never take effect).

## Round 5 update, re-audited at `2cb65fe`

`Wire style.css, search-provider data files, and Heroic/shell-provider test
coverage` landed. Re-identified rather than trusting the commit title:

- **`style.css` is wired now.** `lib/cartridges/application.rb` carries a
  `load_css`/`css_provider` pair calling `Gtk::CssProvider.new.tap { |p|
  p.load_from_path(...) }` and `Gtk::StyleContext.add_provider_for_display`,
  confirmed by reading the file. The dead-file gap above is closed.
- **The search-provider unit's two missing upstream files now have port
  counterparts.** `data/page.kramo.Cartridges.SearchProvider.ini` and
  `data/page.kramo.Cartridges.SearchProvider.service.in` exist and match
  upstream's `search-provider/*.ini`/`*.service.in` content, and
  `cartridges-rb.gemspec` + `Rakefile`'s new `install:search_provider` task
  install them (substituted) to the same two paths upstream's
  `search-provider/meson.build` does. All four upstream files in this unit
  now have a port counterpart.
- **No new upstream file appeared, and no new upstream file went
  unmapped.** The commit's other changes are to `lib/cartridges/application.rb`
  (CSS loading, already-mapped unit) and `test/` (not a component).
- `po/` and gettext calls: unchanged, still absent — see
  `translation-parity.md`.
