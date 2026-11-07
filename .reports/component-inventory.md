# Cartridges component inventory

Survey of upstream (`origin/main`, Python + Blueprint) against the `ruby`
branch's `lib/`. Scope: every user-facing component (windows, dialogs, pages,
rows, menus, shortcuts, actions, empty/error states) plus the GSettings
schema, GResource manifest and `po/` catalogue. This is a map of what exists
and what is missing — not a line-by-line parity audit.

Upstream app id: `page.kramo.Cartridges`. Port namespace: `Cartridges::*`.

## Summary

The `ruby` branch already carries a substantial port — 42 `lib/` files,
~6,900 lines. Most upstream units have a corresponding file. The gaps found:

- **Search provider** (`search-provider/cartridges-search-provider.in`) has
  no `lib/` counterpart at all — this is a separate D-Bus service binary
  (GNOME Shell search integration), not loaded by the main app.
- **`Adw.ShortcutsDialog` rewrite**: upstream's `shortcuts-dialog.blp` uses
  the newer declarative `Adw.ShortcutsDialog`/`Adw.ShortcutsSection`/
  `Adw.ShortcutsItem` widgets; confirm `lib/cartridges/shortcuts_dialog.rb`
  (50 lines) uses the matching Ruby API rather than the older
  `Gtk.ShortcutsWindow` shape.
- No `lib/` file corresponds directly to `data/page.kramo.Cartridges.metainfo.xml.in`
  (About dialog release notes / screenshots) — check `application.rb`'s About
  dialog construction for release notes parity.
- `po/` catalogue (40+ locales) has no Ruby-side equivalent to audit here;
  flagged for `translation-parity`.

## Components, upstream file → port file

### Application / entry point

| Upstream | Port (`lib/`) | Kind | Exists? |
|---|---|---|---|
| `cartridges/main.py` | `cartridges/application.rb` | Adw.Application subclass — actions, accelerators, About dialog, app-level `app.*` actions (`preferences`, `shortcuts`, `about`, `add_game`, `import`, `igdb_search`, `sgdb_search`, `protondb_search`, `pcgw_search`, `lutris_search`, `hltb_search`, plus dynamic per-source import actions and `sort` stateful action) | Yes |
| `cartridges/shared.py.in` / `shared.pyi` | `cartridges/shared.rb` | module-level shared state (schema, store, prefix, paths) | Yes |
| `data/page.kramo.Cartridges.gschema.xml.in` | `cartridges/settings.rb` | GSettings schema wrapper (~40 keys: import toggles/locations per source, sgdb, window geometry, sort-mode, show-sidebar, library-rows, steam-limiter history) | Yes |
| `data/page.kramo.Cartridges.desktop.in` | — (consumed by `application.rb` / packaging) | desktop entry | N/A (packaging, not a widget) |
| `data/page.kramo.Cartridges.metainfo.xml.in` | — (About dialog in `application.rb`) | AppStream metadata — release notes/screenshots feed the About dialog | Partial — verify `application.rb`'s About dialog surfaces release notes |
| `search-provider/cartridges-search-provider.in` + `.ini` + `.service.in` | **none** | standalone D-Bus Shell Search Provider executable (separate process, not a window/dialog) | **Missing** |

### Main window

| Upstream | Port (`lib/`) | Kind | Exists? |
|---|---|---|---|
| `cartridges/window.py` + `data/gtk/window.blp` (`template $CartridgesWindow: Adw.ApplicationWindow`) | `cartridges/window.rb` (593 lines) | main window: `Adw.OverlaySplitView`, sidebar `Gtk.ListBox` (All Games / Added / per-source rows, built dynamically via `create_source_rows`), `Adw.NavigationView` with library/hidden-library/details pages, search bars, toast overlay, breakpoint | Yes |
| window.blp `menu primary_menu` (submenu "Sort" with 5 radio items, Preferences/Shortcuts/About) | `cartridges/window_menus.rb` | menu model | Yes |
| window.blp `menu add_games` (Add Game / Import submenu items, one per source) | `cartridges/window_menus.rb` (and/or `application.rb` for dynamic per-source import actions) | menu model | Yes — verify dynamic per-source item names match `shared.py`'s source list |
| window.blp `menu search` (IGDB/SteamGridDB/ProtonDB/PCGamingWiki/Lutris/HowLongToBeat lookup items) | `cartridges/window_menus.rb` | menu model | Yes |
| `notice_empty` / `notice_no_results` (`Adw.StatusPage`, library empty/search-empty states) | `cartridges/library_notices.rb` | empty-state pages | Yes |
| `hidden_notice_empty` / `hidden_notice_no_results` | `cartridges/library_notices.rb` (shared) or `hidden_library_page.rb` | empty-state pages | Yes — confirm both empty states (not just the visible-library one) are covered |
| Hidden-library `Adw.NavigationPage` (`hidden_library_page`, own header bar, search bar, flow box, menu button) | `cartridges/hidden_library_page.rb` (100 lines) | page | Yes |
| Dynamic sidebar source row (icon + label + count `Gtk.Box`, built in a loop in `create_source_rows`) — **repeater**, one per detected import source, count varies | `cartridges/source_row.rb` | row (repeater) | Yes |
| Details-view overlay inside the window (`details_page`, `details_view_toolbar_view`, cover/blurred-cover pictures, play button, developer/added/last-played labels, hide button) | `cartridges/details_page.rb` (220 lines) | page | Yes |

### Game card / row

| Upstream | Port (`lib/`) | Kind | Exists? |
|---|---|---|---|
| `cartridges/game.py` + `data/gtk/game.blp` (`template $Game: Box`) | `cartridges/game.rb` (235 lines) | library grid cell: cover picture, spinner, play/menu buttons behind hover revealers, `update-ready`/`save-ready` signals | Yes |
| `cartridges/game.py`'s plain-data half (attrs: added/executable/game_id/source/hidden/last_played/name/developer/removed/blacklisted/version) | `cartridges/game_model.rb` (148 lines) | data model, split from the widget — a deliberate port restructuring | Yes |
| game.blp `menu game_options` (Edit/Hide/Remove) | `cartridges/game_menus.rb` | menu model | Yes |
| game.blp `menu hidden_game_options` (Edit/Unhide/Remove) | `cartridges/game_menus.rb` | menu model | Yes |
| `cartridges/game_cover.py` | `cartridges/game_cover.rb` (197 lines) | cover-texture/blur management (`Gtk.Picture` sources) | Yes |

### Dialogs

| Upstream | Port (`lib/`) | Kind | Exists? |
|---|---|---|---|
| `cartridges/details_dialog.py` + `data/gtk/details-dialog.blp` (`template $DetailsDialog: Adw.Dialog`, cover group, name/developer/executable `Adw.EntryRow`s) | `cartridges/details_dialog.rb` (277 lines) | edit-game dialog | Yes |
| `cartridges/utils/create_dialog.py` | `cartridges/create_dialog.rb` (26 lines) | add-game dialog | Yes — check line-count disparity (upstream likely has more fields; confirm no truncation) |
| `cartridges/preferences.py` + `data/gtk/preferences.blp` (`template $CartridgesPreferences: Adw.PreferencesDialog`, 3 pages: General, Import [7 `Adw.ExpanderRow` sources + desktop switch], SGDB) | `cartridges/preferences_dialog.rb` (174 lines) | preferences dialog | Yes |
| `data/gtk/shortcuts-dialog.blp` (`Adw.ShortcutsDialog`, 2 sections, ~11 `Adw.ShortcutsItem`s) — no backing `.py`, pure declarative object | `cartridges/shortcuts_dialog.rb` (50 lines) | standalone dialog (no owning class upstream) | Yes — confirm it targets `Adw.ShortcutsDialog`/`Adw.ShortcutsSection`/`Adw.ShortcutsItem` (newer API), not `Gtk.ShortcutsWindow` |

### Errors

| Upstream | Port (`lib/`) | Kind | Exists? |
|---|---|---|---|
| `cartridges/errors/error_producer.py` | `cartridges/error_producer.rb` | error-state mixin/dispatch | Yes |
| `cartridges/errors/friendly_error.py` | `cartridges/friendly_error.rb` | user-facing error message mapping | Yes |

### Importers (per-source, non-widget but user-facing: feeds sidebar rows, preferences expander rows, and toasts)

| Upstream | Port (`lib/importer`) | Exists? |
|---|---|---|
| `importer/bottles_source.py` | `importer/bottles_source.rb` | Yes |
| `importer/desktop_source.py` | `importer/desktop_source.rb` | Yes |
| `importer/flatpak_source.py` | `importer/flatpak_source.rb` | Yes |
| `importer/heroic_source.py` | `importer/heroic_source.rb` | Yes |
| `importer/importer.py` | `importer/importer.rb` | Yes |
| `importer/itch_source.py` | `importer/itch_source.rb` | Yes |
| `importer/legendary_source.py` | `importer/legendary_source.rb` | Yes |
| `importer/location.py` | `importer/location.rb` | Yes |
| `importer/lutris_source.py` | `importer/lutris_source.rb` | Yes |
| `importer/retroarch_source.py` | `importer/retroarch_source.rb` | Yes |
| `importer/source.py` | `importer/source.rb` | Yes |
| `importer/steam_source.py` | `importer/steam_source.rb` | Yes |

### Store / managers (background pipeline feeding game covers, SGDB, Steam API)

| Upstream | Port (`lib/`) | Exists? |
|---|---|---|
| `store/store.py` | `cartridges/store.rb` | Yes |
| `store/pipeline.py` | `cartridges/store/pipeline.rb` | Yes |
| `store/managers/manager.py` | `store/managers/manager.rb` | Yes |
| `store/managers/async_manager.py` | `store/managers/async_manager.rb` | Yes |
| `store/managers/cover_manager.py` | `store/managers/cover_manager.rb` | Yes |
| `store/managers/display_manager.py` | `store/managers/display_manager.rb` | Yes |
| `store/managers/file_manager.py` | `store/managers/file_manager.rb` | Yes |
| `store/managers/sgdb_manager.py` | `store/managers/sgdb_manager.rb` | Yes |
| `store/managers/steam_api_manager.py` | `store/managers/steam_api_manager.rb` | Yes |

### Utils / logging (non-widget support code, listed because preferences rows and toasts depend on them)

| Upstream | Port (`lib/`) | Exists? |
|---|---|---|
| `utils/rate_limiter.py` | `cartridges/rate_limiter.rb` | Yes |
| `utils/relative_date.py` | `cartridges/relative_date.rb` | Yes (feeds "Added"/"Last played" labels on details page) |
| `utils/run_executable.py` | `cartridges/run_executable.rb` | Yes |
| `utils/save_cover.py` | `cartridges/save_cover.rb` | Yes |
| `utils/sqlite.py` | `cartridges/sqlite.rb` | Yes |
| `utils/steamgriddb.py` | `cartridges/steamgriddb.rb` | Yes |
| `utils/steam.py` | `cartridges/steam.rb` | Yes |
| `logging/color_log_formatter.py` | `logging/color_log_formatter.rb` | Yes |
| `logging/session_file_handler.py` | `logging/session_file_handler.rb` | Yes |
| `logging/setup.py` | `logging/setup.rb` | Yes |

### Not yet accounted for in this pass

| File | Note |
|---|---|
| `lib/cartridges/http_client.rb` | present in `lib/` with no single obvious 1:1 upstream file name — likely factored out of `utils/steamgriddb.py`/`utils/steam.py`'s shared HTTP logic (requests/urllib calls inline upstream). Not a gap, but worth noting as a port-side restructuring to confirm against both call sites. |
| `po/*.po` (43 locale files) + `po/cartridges.pot` + `po/LINGUAS` | translation catalogue — not assessed here; flagged for the `translation-parity` skill. |
| `data/icons/sources/*-source-symbolic.svg` (8 per-source icons) | asset parity (icons referenced by sidebar/preferences rows) — not assessed here, flagged for asset/icon parity pass. |
| `data/library_placeholder.svg`, `data/library_placeholder_small.svg` | empty-state artwork referenced by `notice_empty`/`hidden_notice_empty` — confirm these ship in the port's resources. |
| `data/gtk/style.css`, `data/gtk/style-dark.css` | `lib/cartridges/style.css` exists as a single file — confirm it merges both light/dark rule sets (upstream ships them separately, loaded conditionally). |

## Recommended next steps (not performed in this pass — this is a survey only)

1. Run `component-parity` on `window.rb` vs `window.py`+`window.blp` first (largest, most central file) to get widget/CSS/signal-level diff, not just presence.
2. Decide whether the search-provider D-Bus service is in scope for this port at all (it's a separate executable, not a GTK widget tree) — if yes, it needs its own `bin/`-style entry point, not a `lib/*.rb` widget class.
3. Verify `shortcuts_dialog.rb` targets the `Adw.ShortcutsDialog` API family (upstream has already migrated off `Gtk.ShortcutsWindow`).
4. Confirm `create_dialog.rb` (only 26 lines) isn't missing fields present in `utils/create_dialog.py`.
