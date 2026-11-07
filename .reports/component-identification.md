# Component identification — cartridges-rb

| | |
|---|---|
| Upstream | `origin/main` @ `c4454fd` |
| Port | `ruby` @ `6e281e9` |

This supersedes nothing in `.reports/component-inventory.md` (the pre-build
planning inventory); it re-identifies both trees as they stand now, after the
port landed, to feed `component-parity`. It also supersedes the prior round
of this report (written at `fb67b2f`), which found Lutris, Heroic and itch
unported; two commits landed since (`Port Importer::HeroicSource` and `Port
Lutris and itch importer sources`) and are re-checked below.

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
| `search-provider/*` (`.in` exe, `.service.in`, `.ini`) | — | **no file, no `exe/` entry, no D-Bus service anywhere in the port** |

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
- The search-provider D-Bus service still has **zero** port counterpart —
  re-confirmed this round (`git ls-tree -r --name-only origin/main | grep
  search-provider` still lists four upstream files; `find`/`grep -rn
  SearchProvider` over the port tree still return nothing).
- There is still no `po/` directory and (confirmed by grep, see
  `translation-parity.md`) no gettext call anywhere in `lib/`. Unchanged
  from the prior round.
- `lib/cartridges/style.css` (flagged in `component-inventory.md` as
  present but unwired) is still never referenced by any `Gtk::CssProvider`
  call anywhere in `lib/` or `exe/` (re-confirmed this round by grep) — a
  shipped file with dead CSS, not a missing one, so it does not show up as
  an absent port file but is a real behavioural gap (the purple accent
  overrides and `#details_view` rules it defines never take effect).
