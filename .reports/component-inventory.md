# cartridges-rb — upstream component inventory

Survey of `origin/main` (upstream Cartridges, Python + blueprint + GTK4/Libadwaita)
against `lib/` on the `ruby` branch. No app code was written in this step.

Method: the `component-identification` skill. Upstream has five blueprint files,
so those were read first — they *are* the component inventory for everything built
at startup — then the Python that backs them was read for runtime-built widgets,
dynamic CSS classes, signal wiring and actions.

Upstream shape: `@Gtk.Template(resource_path=…)` classes in `cartridges/*.py`
paired with `data/gtk/*.blp`. **The component is the pair**, so each row below
unions the `.blp` tree with the `.py` callbacks.

Port layout: `lib/cartridges/<thing>.rb` under `module Cartridges`, matching the
`lib/cartridges/application.rb` that already exists. One upstream source file (or
blueprint/source pair) becomes one file.

Current state of `lib/` on `ruby`:

```
lib/cartridges.rb                 # requires cartridges/application
lib/cartridges/application.rb     # stub: window + header bar + "not written yet" StatusPage
lib/cartridges/rb/version.rb
```

So **one** of the components below exists, and it exists as a placeholder. Totals:
5 blueprint files, 5 template/standalone-root units, 5 standalone menu models,
4 standalone status pages, 1 shortcuts dialog, 2 GSettings schemas (42 keys),
38 translated locales.

---

## 1. `cartridges/main.py` — the application: actions, accelerators, About

→ `lib/cartridges/application.rb` · kind: application · **exists (stub only)**

Not a widget class, but it owns every `app.*` action, every accelerator, the
About dialog and the Preferences entry point, so it is its own unit.

| Widget | × | CSS | Signals | Notes |
|---|---:|---|---|---|
| `Adw.AboutDialog` | 1 | — | — | `new_from_appdata(metainfo.xml, VERSION)`; 9 developers, 1 designer, copyright, `translator-credits`, debug info from the log files (xz-aware, `─`×37 between runs), `debug_info_filename = "cartridges.log"`, extra legal section "Steam Branding" |
| `Gtk.Settings` | — | — | — | macOS only: `gtk_decoration_layout = "close,minimize,maximize:"` |

Actions installed on `app` (all `Gio::SimpleAction`, built from a set literal in
`create_actions`, so **none of them appear in a textual scan** — they were read
off the literal):

| Action | Accel | Does |
|---|---|---|
| `app.quit` | `<primary>q` | quit |
| `app.about` | — | About dialog |
| `app.preferences` | `<primary>comma` | Preferences dialog (single-instance via `is_open`) |
| `app.launch_game` | — | `win.active_game.launch` |
| `app.hide_game` | — | `win.active_game.toggle_hidden` |
| `app.edit_game` | — | `DetailsDialog(active_game)` |
| `app.add_game` | `<primary>n` | `DetailsDialog()` (single-instance) |
| `app.import` | `<primary>i` | build `Importer`, add every enabled source, run |
| `app.remove_game` | — | `active_game.remove_game` |
| `app.remove_game_details_view` | `Delete` | remove, but only when the details page is visible |
| `app.igdb_search` | — | opens `igdb.com/search?type=1&q=` + game name |
| `app.sgdb_search` | — | `steamgriddb.com/search/grids?term=` |
| `app.protondb_search` | — | `protondb.com/search?q=` |
| `app.pcgw_search` | — | `pcgamingwiki.com/w/index.php?search=` |
| `app.lutris_search` | — | `lutris.net/games?q=` |
| `app.hltb_search` | — | `howlongtobeat.com/?q=` |

Window-scoped actions are installed here too but handled in `window.py` (see §2).
`<primary>` is rewritten to `<meta>` on darwin.

Also: `--search TERM` / `-s` and `--launch GAME_ID` / `-l` command-line options
(`do_handle_local_options`); `-l` runs the game headlessly and posts a
`Gio::Notification` `"{} launched"`, then withdraws it after 6 s. State-schema
bindings for `width`, `height`, `is-maximized`. A stateful `win.sort_by` action
of type `s` seeded from `sort-mode`. Auto-import on startup when `auto-import`.

---

## 2. `data/gtk/window.blp` + `cartridges/window.py` — main window & library

→ `lib/cartridges/window.rb` · kind: window · **missing**

`template $CartridgesWindow: Adw.ApplicationWindow`, title "Cartridges",
`width-request: 360`, `height-request: 100`.

| Widget | × | CSS | Signals / bindings | Notes |
|---|---:|---|---|---|
| `Adw.ApplicationWindow` | 1 | `devel` (dynamic, when `PROFILE == "development"`) | — | template root |
| `Adw.Breakpoint` | 1 | — | — | `max-width: 564px`; 13 setters collapsing the split view and re-stacking the details view (see list below) |
| `Adw.ToastOverlay` | 1 | — | — | `toast_overlay`, every toast in the app lands here |
| `Adw.NavigationView` | 1 | — | `popped`, `pushed` → `set_show_hidden` | also the `key-capture-widget` of `search_bar` |
| `Adw.NavigationPage` | 2 | — | — | `library_page` ("All Games", title retitled per selected source), `sidebar_navigation_page` ("Cartridges"; set to `""` on darwin) |
| `Adw.OverlaySplitView` | 1 | — | — | `sidebar-width-fraction: .2`; `show-sidebar` seeded from and written to the `show-sidebar` state key |
| `Adw.ToolbarView` | 2 | — | — | sidebar's, and `library_view` |
| `Adw.HeaderBar` | 2 | — | — | sidebar's (holds one sidebar-toggle button), `header_bar` |
| `Gtk.Button` | 2 | — | `action-name: win.show_sidebar` | both tooltipped "Toggle Sidebar"; `show_sidebar_button`'s `visible` is bound to `overlay_split_view.show-sidebar` **inverted** |
| `Gtk.MenuButton` | 2 | — | — | "Add Game" (`list-add-symbolic`, `add_games` menu), `primary_menu_button` ("Main Menu", `open-menu-symbolic`, `primary_menu`); the latter is `popup()`ed by `win.open_menu` |
| `Gtk.ToggleButton` | 1 | — | `action-name: win.toggle_search` | `search_button`, "Search" |
| `Gtk.SearchBar` | 1 | — | `search-mode-enabled` ↔ `search_button.active` (bidirectional) | `connect_entry(search_entry)` in code |
| `Gtk.SearchEntry` | 1 | — | `search-changed` → `search_changed(false)`, `activate` → `show_details_page_search` | placeholder "Search" |
| `Gtk.ShortcutController` + `Gtk.Shortcut` | 1 + 1 | — | trigger `Escape` → `action(win.toggle_search)` | on the search entry — **behaviour, not a widget count** |
| `Adw.Clamp` | 1 | — | — | `maximum-size`/`tightening-threshold` 500, wraps the search entry |
| `Gtk.Overlay` | 1 | — | — | `library_overlay`; empty-state pages are added to / removed from it at runtime |
| `Gtk.ScrolledWindow` | 1 | — | — | `scrolledwindow` |
| `Gtk.FlowBox` | 1 | `no-hover` | `set_filter_func(filter_func)`, `set_sort_func(sort_func)` | `library`; homogeneous, 12 px gaps, 15 px margins, `selection-mode: none`; `max-children-per-line` bound to `library-rows` when non-zero, else 10 |
| `Gtk.ListBox` | 1 | `navigation-sidebar` | `row-selected` → `row_selected` | `sidebar` |
| `Gtk.Box` | 2 | — | — | `all_games_row_box` (view-grid icon + "All Games" + count), `added_row_box` (list-add icon + "Added" + count; hidden when nothing was imported) |
| `Gtk.Image` | 2 | — | — | `view-grid-symbolic`, `list-add-symbolic` |
| `Gtk.Label` | 4 | `dim-label` (on the two count labels), `heading` (on "Imported") | — | "All Games", `all_games_no_label`, "Added", `added_games_no_label`, plus the "Imported" header label |
| `Gtk.ListBoxRow` | 1 | — | — | the non-selectable, non-activatable "Imported" section header; shown only when at least one imported source row exists |
| `Gtk.EventControllerMotion` | — | — | — | (none here; see §5) |

Breakpoint setters (`max-width: 564px`): `overlay_split_view.collapsed`;
`details_view_box` → vertical + 12 px margins; `details_view_details_box`
margins → 0; `details_view_title` margin-top 30 + centred;
`details_view_developer`, `details_view_date_box`, `details_view_toolbar`
centred; `details_view_toolbar` → vertical; `details_view_play_button` centred;
`details_view_toolbar_buttons.margin-start: 0`.

Window actions (installed by `main.py`, handled here):

| Action | Accel | Does |
|---|---|---|
| `win.show_sidebar` | `F9` | toggle + persist `show-sidebar` |
| `win.show_hidden` | `<primary>h` | push the hidden-library page; **enabled only while the library page is visible** |
| `win.go_to_parent` | `<alt>Up` | pop the details page |
| `win.go_home` | `<alt>Home` | `pop_to_page(library_page)` |
| `win.toggle_search` | `<primary>f` | toggle whichever search bar belongs to the visible page; focuses and clears the entry |
| `win.undo` | `<primary>z` | undo the last import, else the newest hide/remove toast |
| `win.open_menu` | `F10` | `popup()` the visible page's primary menu button |
| `win.close` | `<primary>w` | close the window |
| `win.sort_by` | — | stateful `s`; `a-z`, `z-a`, `newest`, `oldest`, `last_played`; persisted to `sort-mode` |

Non-widget behaviour that has to be ported with it: `filter_func` (search text
over name + developer, then source filter, then recompute the empty state),
`sort_func` (five modes, `"the "` prefix stripped, name as tiebreak),
`set_library_child` (chooses between four status pages and adds/removes them as
overlays), `show_details_page`, `set_details_view_opacity` (blur opacity from
cover luminance, light/dark, high-contrast fallback 0.3),
`show_details_page_search` (Enter in the search entry opens the first match),
and `Adw.StyleManager` `notify::dark` / `notify::high-contrast` connections.

**Repeaters:** the sidebar source rows (§4) and the library tiles (§5) — one
`Game` per store entry, two flow boxes.

---

## 3. `data/gtk/window.blp` (standalone roots) — pages, menus, empty states

These are declared at column 0 in `window.blp` with no backing widget subclass,
so per the skill they are their own units.

### 3a. `hidden_library_page` → `lib/cartridges/hidden_library_page.rb` · kind: page · **missing**

| Widget | × | CSS | Signals | Notes |
|---|---:|---|---|---|
| `Adw.NavigationPage` | 1 | — | — | "Hidden Games" |
| `Adw.ToolbarView` | 1 | `background` | — | `hidden_library_view`, also the search bar's key-capture widget |
| `Adw.HeaderBar` | 1 | — | — | `hidden_header_bar` |
| `Gtk.MenuButton` | 1 | — | — | `hidden_primary_menu_button`, `primary_menu` |
| `Gtk.ToggleButton` | 1 | — | `win.toggle_search` | `hidden_search_button` |
| `Gtk.SearchBar` | 1 | — | bound to `hidden_search_button.active` | no Escape shortcut here (upstream asymmetry — keep it) |
| `Adw.Clamp` | 1 | — | — | 500/500 |
| `Gtk.SearchEntry` | 1 | — | `search-changed` → `search_changed(true)`, `activate` → `show_details_page_search` | |
| `Gtk.Overlay` | 1 | — | — | `hidden_library_overlay` |
| `Gtk.ScrolledWindow` | 1 | — | — | |
| `Gtk.FlowBox` | 1 | `no-hover` | own filter + sort funcs | `hidden_library` |

### 3b. `details_page` → `lib/cartridges/details_page.rb` · kind: page · **missing**

| Widget | × | CSS | Signals | Notes |
|---|---:|---|---|---|
| `Adw.NavigationPage` | 1 | — | — | "Game Details", retitled to the game name |
| `Gtk.Overlay` | 1 | — | — | `details_view`, `name: "details_view"` → styled by `#details_view` (white / black in dark) |
| `Adw.ToolbarView` | 1 | — | — | `details_view_toolbar_view`; registered as a measured, non-clipped overlay child |
| `Adw.HeaderBar` | 1 | — | — | empty |
| `Gtk.ScrolledWindow` | 1 | — | — | |
| `Gtk.Box` | 4 | — | — | `details_view_box`, `details_view_details_box`, `details_view_date_box`, `details_view_toolbar` + `details_view_toolbar_buttons` (`toolbar`) |
| `Adw.Clamp` | 1 | — | — | 200 |
| `Gtk.Overlay` | 1 | — | — | spinner over cover |
| `Adw.Spinner` | 1 | — | — | `details_view_spinner`, visible while the game is loading |
| `Gtk.Picture` | 2 | `card` (cover only) | — | `details_view_cover` 200×300; `details_view_blurred_cover` (`keep-aspect-ratio: false`, opacity from luminance) |
| `Gtk.Label` | 4 | `title-1`, `heading` | — | title, developer (hidden when blank), "Added: {}", "Last played: {}" / "Never" |
| `Gtk.Button` | 4 | `opaque`+`pill`; `raised`+`circular` ×3 | `app.launch_game`, `app.edit_game`, `app.hide_game`, `app.remove_game` | play button has `name: "details_view_play_button"` → styled by `#details_view_play_button`; the hide button's icon/tooltip flip between `view-conceal-symbolic`/"Hide" and `view-reveal-symbolic`/"Unhide" |
| `Gtk.MenuButton` | 1 | `raised`, `circular` | — | `search` menu, "Search" |

### 3c. Library empty / no-result states → `lib/cartridges/library_notices.rb` · kind: empty-state · **missing**

Four standalone `Adw.StatusPage`s, `vexpand`, `valign: center`, added to and
removed from the two library overlays by `set_library_child`:

| Object | Icon | Title | Description | Extra |
|---|---|---|---|---|
| `notice_empty` | `shared.APP_ID + "-symbolic"` (set in code) | "No Games" | "Use the + button to add games" | child `Gtk.Button` "Import", `pill` + `suggested-action`, `app.import` |
| `notice_no_results` | `system-search-symbolic` | "No Games Found" | "Try a different search" | — |
| `hidden_notice_empty` | `view-conceal-symbolic` | "No Hidden Games" | "Games you hide will appear here" | — |
| `hidden_notice_no_results` | `system-search-symbolic` | "No Games Found" | "Try a different search" | — |

### 3d. Window menu models → `lib/cartridges/window_menus.rb` · kind: menu · **missing**

All lowercase blueprint keywords, so a scan reports nothing — counted by hand.

| Menu | Items | Notes |
|---|---:|---|
| `primary_menu` | 9 | section 1: "Sort" submenu with 5 targeted items on `win.sort_by` (`a-z`, `z-a`, `newest`, `oldest`, `last_played`) + "Show Hidden" (`win.show_hidden`, `hidden-when: action-disabled`); section 2: Preferences, Keyboard Shortcuts, About Cartridges |
| `add_games` | 2 | "Add Game" (`app.add_game`), "Import" (`app.import`) |
| `search` | 6 | section labelled "Search on…": IGDB, SteamGridDB, ProtonDB, PCGamingWiki, Lutris, HowLongToBeat |

---

## 4. `cartridges/window.py` `create_source_rows` — sidebar source rows

→ `lib/cartridges/source_row.rb` · kind: row (repeater) · **missing**

Built in a loop, so one textual occurrence and N rows on screen. One per source
in the store that still has non-removed games, inserted below the "Imported"
header and **ordered by game count**, descending.

| Widget | × | CSS | Signals | Notes |
|---|---:|---|---|---|
| `Gtk.Box` | 1 / row | — | — | 12 px top/bottom, 6 px start/end, spacing 12 |
| `Gtk.Image` | 1 / row | — | — | `user-desktop-symbolic` for the desktop source, else `{source}-source-symbolic` from the bundled icon set |
| `Gtk.Label` | 2 / row | `dim-label` (count label, added dynamically) | — | localised source name; game count |

Behaviour: preserves the selected row across rebuilds, hides the "Added" row and
the "Imported" header when empty, recomputes the "All Games" total, falls back to
selecting "All Games". Selecting a row retitles `library_page`, sets
`filter_state` and invalidates the flow box filter; collapses the sidebar when
the split view is collapsed.

---

## 5. `data/gtk/game.blp` + `cartridges/game.py` — the library tile

→ `lib/cartridges/game.rb` · kind: tile (repeater) · **missing**

`template $Game: Box`, vertical, `halign: center`, `valign: start`. One per game,
repeated into both flow boxes.

| Widget | × | CSS | Signals | Notes |
|---|---:|---|---|---|
| `Gtk.Box` | 2 | — | — | template root; inner vertical box inside the cover button |
| `Adw.Clamp` | 1 | — | — | `maximum-size: 200`, `unit: px` |
| `Gtk.Overlay` | 2 | — | — | outer (revealers over the cover button), inner (spinner over cover) |
| `Gtk.Revealer` | 2 | — | — | `play_revealer` (crossfade, top-start), `menu_revealer` (crossfade, top-end); both revealed on pointer enter and hidden on leave, **unless the menu button is active** |
| `Gtk.Button` | 2 | `circular`+`osd`; `card` | `clicked` → `main_button_clicked(true)` / `(false)` | `play_button` (icon flips between `media-playback-start-symbolic` and `help-about-symbolic` on the `cover-launches-game` setting); `cover_button` (`name: "cover_button"`, `overflow: hidden`, `labelled-by: title`) |
| `Gtk.MenuButton` | 1 | `circular`, `osd` | — | `menu_button`, `view-more-symbolic`; model swapped between `game_options` and `hidden_game_options` |
| `Adw.Spinner` | 1 | — | — | `spinner`, visible while `loading > 0`; cover opacity goes to 0 |
| `Gtk.Picture` | 1 | — | — | `cover` 200×300, h/vexpand |
| `Gtk.Label` | 1 | — | — | `title`, `ellipsize: end`, 15/12 px margins |
| `Gtk.EventControllerMotion` | 1 | — | `enter`, `leave` → `toggle_play` | **controller, not a widget** |

Toasts raised from here (all into `win.toast_overlay`, `ToastPriority::HIGH`,
`use_markup = false`): `"{} launched"`, `"{} hidden"` / `"{} unhidden"` (with an
"Undo" button), `"{} removed"` (with "Undo"). Duplicate toasts for the same
(game, action) pair are dismissed first. Custom GObject signals `update-ready`
and `save-ready`. `cover_button` click launches or opens the details page
depending on `cover-launches-game` XOR which button was clicked.

### 5a. Game menu models → `lib/cartridges/game_menus.rb` · kind: menu · **missing**

| Menu | Items |
|---|---|
| `game_options` | Edit (`app.edit_game`), Hide (`app.hide_game`), Remove (`app.remove_game`) |
| `hidden_game_options` | Edit, **Unhide** (same `app.hide_game`), Remove |

---

## 6. `cartridges/game_cover.py` — cover paintable, blur and luminance

→ `lib/cartridges/game_cover.rb` · kind: model (drives widgets) · **missing**

Not a widget, but it owns every `Gtk::Picture` in the app. Holds a set of
pictures and pushes a `Gdk::Texture` into all of them; placeholder textures
`library_placeholder.svg` and `library_placeholder_small.svg` from the resource
bundle; animated GIF covers advanced on a timeout (min 20 ms) via
`GdkPixbuf::PixbufAnimationIter`; `get_blurred` produces a 100×150 Gaussian-blur
(radius 20) TIFF texture and a light/dark luminance pair used for the details
view's blurred backdrop opacity.

**Blocker:** upstream uses PIL for the blur, the composite and the luminance
statistics. Ruby has no PIL; this needs a GdkPixbuf/Cairo or `ruby-vips`
equivalent, and the luminance formula
(`min((mean+min)/510, 0.7)`, `max((mean+max)/510, 0.3)`) reproduced exactly or
the details view's backdrop will look different.

---

## 7. `data/gtk/details-dialog.blp` + `cartridges/details_dialog.py` — add / edit game

→ `lib/cartridges/details_dialog.rb` · kind: dialog · **missing**

`template $DetailsDialog: Adw.Dialog`, `content-width: 480`. Title and apply
label swap between "Game Details"/"Apply" and "Add New Game"/"Add".
Single-instance via a class-level `is_open` flag reset on `closed`.

| Widget | × | CSS | Signals | Notes |
|---|---:|---|---|---|
| `Adw.Dialog` | 1 | — | `closed` | template root |
| `Adw.ToolbarView` | 1 | — | — | |
| `Adw.HeaderBar` | 1 | — | — | both title-button sets off |
| `Gtk.Button` | 4 | `suggested-action`; `circular`+`osd` ×2; `flat` | `window.close`; `clicked` → `apply_preferences`, `choose_cover`, `delete_pixbuf`, `choose_executable` | Cancel; `apply_button`; `cover_button_edit` ("New Cover"); `cover_button_delete` ("Delete Cover"); `file_chooser_button` ("Select File", `document-open-symbolic`) |
| `Adw.PreferencesPage` | 1 | — | — | |
| `Adw.PreferencesGroup` | 3 | — | — | cover, name/developer, executable |
| `Adw.Clamp` | 1 | — | — | 200 |
| `Gtk.Overlay` | 2 | — | — | spinner over cover; `cover_overlay` for the two cover buttons |
| `Adw.Spinner` | 1 | — | — | visible while a cover is being converted |
| `Gtk.Revealer` | 1 | — | — | `cover_button_delete_revealer`, crossfade, revealed only when a cover exists |
| `Gtk.Picture` | 1 | `card` | — | `cover` 200×300 |
| `Adw.EntryRow` | 3 | — | `entry-activated` → focus executable / apply | "Title", "Developer (optional)", "Executable" |
| `Gtk.MenuButton` | 1 | `flat` | — | `exec_info_button`, `help-about-symbolic`, "More Info" |
| `Gtk.Popover` | 1 | — | `show` → grab focus (a11y) | `exec_info_popover`, `focusable` |
| `Gtk.Label` | 1 | — | — | `exec_info_label`, markup, 50 chars; long platform-specific help text with `<tt>` command samples (win32 `start`, darwin `open`, else `xdg-open`) |
| `Gtk.FileDialog` | 2 | — | — | images (every PIL-registered extension minus `.palm`/`.pdf`, plus `svg`) and executables (`application/x-executable`) — **types, not widgets** |
| `Gtk.FileFilter` | 2 | — | — | named "Images" and "Executables" |

Error states, all through `create_dialog` (§10): "Couldn't Add Game" /
"Couldn't Apply Preferences" × "Game title cannot be empty." /
"Executable cannot be empty."; and the SteamGridDB auth failure, which offers a
"Preferences" response that opens the `sgdb` page.

New games get id `imported_<n+1>`; adding one selects the "Added" sidebar row
when a source row was selected. A missing cover triggers an SGDB fetch with the
tile in its loading state. The a11y label on the popover strips `<tt>` markup.

---

## 8. `data/gtk/preferences.blp` + `cartridges/preferences.py` — preferences

→ `lib/cartridges/preferences_dialog.rb` · kind: preferences · **missing**

`template $CartridgesPreferences: Adw.PreferencesDialog`, `search-enabled: true`,
single-instance via `is_open`. Three pages.

| Widget | × | CSS | Signals | Notes |
|---|---:|---|---|---|
| `Adw.PreferencesDialog` | 1 | — | `closed` | |
| `Adw.PreferencesPage` | 3 | — | — | `general` ("General", `user-home-symbolic`), `import` ("Import", `document-save-symbolic`), `sgdb` ("SteamGridDB", `image-x-generic-symbolic`) |
| `Adw.PreferencesGroup` | 8 | — | — | Behavior, Images, Danger Zone (`separate-rows`), import Behavior, Sources (`separate-rows`), Authentication, sgdb Behavior, the untitled Update-Covers group |
| `Adw.SwitchRow` | 16 | — | all bound to GSettings `active` | exit-after-launch, cover-launches-game, high-quality-images, auto-import, remove-missing, lutris-import-steam, lutris-import-flatpak, heroic-import-epic/gog/amazon/sideload, flatpak-import-launchers, sgdb, sgdb-prefer, sgdb-animated, desktop (the desktop row carries a `user-desktop-symbolic` prefix image and is hidden when the source is unavailable) |
| `Adw.ButtonRow` | 2 | `destructive-action` ×2 | `activated` → `remove_all_games`, `reset_app` | "Remove All Games"; "Reset App" (visible only when `PROFILE == "development"`) |
| `Adw.ExpanderRow` | 8 | — | `enable-expansion` bound to the source's GSettings key | Steam, Lutris, Heroic, Bottles, itch, Legendary, RetroArch, Flatpak — each `show-enable-switch`, each with a `{source}-source-symbolic` prefix image; hidden when the source is unavailable |
| `Adw.ActionRow` | 11 | `property` ×10 | — | 10 "Install Location" / "System Location" / "User Location" rows (one per source location, two for Flatpak), subtitled with the resolved path (Flatpak portal prefix stripped, `$HOME` → `~`); plus "Update Covers" / "Fetch covers for games already in your library", `sensitive` bound to `sgdb_switch.active` |
| `Gtk.Button` | 11 | `flat` ×10 | `clicked` → `choose_folder(set_dir, location)` | 10 `folder-symbolic` directory pickers; `sgdb_fetch_button` "Update" |
| `Adw.EntryRow` | 1 | — | `changed` → persist `sgdb-key`, re-evaluate `sgdb_switch` sensitivity | "API Key"; the group description carries a link to the SteamGridDB API page |
| `Gtk.Stack` | 1 | — | — | `sgdb_stack`, swaps the Update button for a spinner |
| `Adw.Spinner` | 1 | — | — | `sgdb_spinner` |
| `Gtk.Image` | 9 | — | — | the eight source icons + `user-desktop-symbolic` |
| `Gtk.MenuButton` | 0..9 | `warning` (dynamic) | `show` → focus (a11y) | **built in a loop, not in the blueprint**: one `dialog-warning-symbolic` prefix per source whose location cannot be resolved, tooltip "Warning", holding a `Gtk.Popover` + markup `Gtk.Label` "Installation Not Found" / "Select a valid directory" |
| `Gtk.Popover` | 0..9 | — | `show` | the warning popovers |
| `Gtk.FileDialog` | 1 | — | — | `select_folder` for every picker — **type, not a widget** |
| `Adw.Toast` | 2+ | — | `button-clicked` → `undo_remove_all` | "All games removed" (+Undo, HIGH); "Downloading covers…"; "Covers updated" (HIGH) |
| `Gtk.ShortcutController` + `Gtk.Shortcut` + `Gtk.CallbackAction` | 1 each | — | `<primary>z` → `undo_remove_all` | **controller** |

Error state: "Invalid Directory" + the location's own subtitle
("Select the {} cache/configuration/data directory.", from
`importer/location.py`), with a "Set Location" response that reopens the picker.
Also the SGDB auth error via `create_dialog`.

---

## 9. `data/gtk/shortcuts-dialog.blp` — keyboard shortcuts

→ `lib/cartridges/shortcuts_dialog.rb` · kind: shortcuts · **missing**

Standalone `Adw.ShortcutsDialog` with no backing source file, so its own unit.

| Widget | × | Notes |
|---|---:|---|
| `Adw.ShortcutsDialog` | 1 | |
| `Adw.ShortcutsSection` | 2 | "General", "Games" |
| `Adw.ShortcutsItem` | 11 | General: Search (`win.toggle_search`), Preferences, Keyboard Shortcuts, Undo (`win.undo`), Quit, Toggle Sidebar (`win.show_sidebar`), Main Menu (`win.open_menu`). Games: Add Game, Import, Show Hidden Games (`win.show_hidden`), Remove Game (`app.remove_game_details_view`) |

Accelerators are not in the blueprint — each item resolves its own from the
accels registered in `main.py`, so the two have to stay in step.

---

## 10. `cartridges/importer/importer.py` — import progress, errors, summary

→ `lib/cartridges/importer.rb` · kind: dialog + error-state · **missing**

| Widget | × | CSS | Signals | Notes |
|---|---:|---|---|---|
| `Adw.Dialog` | 1 | — | `close-attempt` → close the main window | `content-width: 350`, `can_close: false`; force-closed by a 100 ms watchdog because of an Adwaita bug |
| `Adw.StatusPage` | 1 | — | — | "Importing Games…" |
| `Gtk.ProgressBar` | 1 | — | — | 12 px side margins; fraction = 10 % sources discovery + 90 % pipelines |
| `Adw.AlertDialog` | 1 | — | `response` → dismiss / open the import preferences page | heading "Warning", responses "Dismiss" and "Preferences" (default). One error → heading+body are the error; several → body "The following errors occured during import:" plus a list |
| `Gtk.ListBox` | 0..1 | `boxed-list` | — | only in the multi-error dialog, `selection-mode: none`, 9 px top margin |
| `Adw.ActionRow` | 0..N | — | — | **repeater**: one per distinct friendly error, title + subtitle |
| `Adw.Toast` | 1 | — | `button-clicked` → `undo_import` or open preferences | `timeout: 0`, HIGH. "No new games found" (+"Preferences" when nothing was removed either), or ngettext "{} game imported"/"{} games imported", with ngettext ", {} removed" appended; +"Undo" when anything changed. Suppressed when an auto-import found and removed nothing. Timed out manually 5 s after the last warning is dismissed |

Also disables and re-enables `app.import`, `app.add_game` and `app.preferences`
for the duration, and rebuilds the sidebar source rows when done.

---

## 11. `cartridges/utils/create_dialog.py` — the alert-dialog helper

→ `lib/cartridges/create_dialog.rb` · kind: dialog helper · **missing**

One function. `Adw.AlertDialog.new(heading, body)` with a "Dismiss" response and
an optional extra response/label, then `choose(win)`. Used by the details dialog
and the preferences dialog for every error state above.

---

## 12. `cartridges/utils/relative_date.py` — user-visible dates

→ `lib/cartridges/relative_date.rb` · kind: formatter · **missing**

Feeds "Added: {}" and "Last played: {}" on the details page. Returns "Today",
"Yesterday", a `%A` weekday, "Last Week", "This Month", "Last Month", a `%B`
month, "Last Year" or `%Y`, in that order of precedence. In POTFILES, so every
string is translated.

---

## 13. Errors

| Upstream | → | Kind | Present |
|---|---|---|---|
| `cartridges/errors/friendly_error.py` | `lib/cartridges/friendly_error.rb` | error model (title/subtitle shown to the user) | missing |
| `cartridges/errors/error_producer.py` | `lib/cartridges/error_producer.rb` | mixin, thread-safe error collection | missing |

Only `FriendlyError`s reach the UI; everything else is logged. The importer and
the managers are both `ErrorProducer`s and their errors are drained into §10's
alert dialog.

---

## 14. Import sources — the data behind the Sources page

Nine sources. Each contributes a localised **name** (shown in the sidebar and in
the "Select the {} … directory." error), an `is_available` test that decides
whether its preferences row is visible at all, and one or more `Location`s that
back an "Install Location" row and its warning popover.

| Upstream | → | Kind | Present |
|---|---|---|---|
| `cartridges/importer/source.py` | `lib/cartridges/importer/source.rb` | base class, `SourceIterable` | missing |
| `cartridges/importer/location.py` | `lib/cartridges/importer/location.rb` | location resolution; owns `CACHE_/CONFIG_/DATA_INVALID_SUBTITLE` and `UnresolvableLocationError` | missing |
| `cartridges/importer/steam_source.py` | `lib/cartridges/importer/steam_source.rb` | source — "Steam" | missing |
| `cartridges/importer/lutris_source.py` | `lib/cartridges/importer/lutris_source.rb` | source — "Lutris" (2 locations) | missing |
| `cartridges/importer/heroic_source.py` | `lib/cartridges/importer/heroic_source.rb` | source — "Heroic" (Epic/GOG/Amazon/sideload sub-sources) | missing |
| `cartridges/importer/bottles_source.py` | `lib/cartridges/importer/bottles_source.rb` | source — "Bottles" | missing |
| `cartridges/importer/itch_source.py` | `lib/cartridges/importer/itch_source.rb` | source — "itch" | missing |
| `cartridges/importer/legendary_source.py` | `lib/cartridges/importer/legendary_source.rb` | source — "Legendary" | missing |
| `cartridges/importer/retroarch_source.py` | `lib/cartridges/importer/retroarch_source.rb` | source — "RetroArch"; raises the friendly error "No RetroArch Core Selected" / "The following playlists have no default core:" / "Games with no core selected were not imported" | missing |
| `cartridges/importer/flatpak_source.py` | `lib/cartridges/importer/flatpak_source.rb` | source — "Flatpak" (2 locations) | missing |
| `cartridges/importer/desktop_source.py` | `lib/cartridges/importer/desktop_source.rb` | source — "Desktop Entries" (switch row, not expander) | missing |

---

## 15. Store and managers — not widgets, but the port cannot show anything without them

| Upstream | → | Kind | Present |
|---|---|---|---|
| `cartridges/store/store.py` | `lib/cartridges/store.rb` | store | missing |
| `cartridges/store/pipeline.py` | `lib/cartridges/store/pipeline.rb` | pipeline, emits `advanced` (drives the progress bar) | missing |
| `cartridges/store/managers/manager.py` | `lib/cartridges/store/managers/manager.rb` | base | missing |
| `cartridges/store/managers/async_manager.py` | `lib/cartridges/store/managers/async_manager.rb` | base, cancellable | missing |
| `cartridges/store/managers/file_manager.py` | `lib/cartridges/store/managers/file_manager.rb` | persists game JSON | missing |
| `cartridges/store/managers/display_manager.py` | `lib/cartridges/store/managers/display_manager.rb` | **adds/removes the `Game` tiles in the flow boxes** | missing |
| `cartridges/store/managers/cover_manager.py` | `lib/cartridges/store/managers/cover_manager.rb` | cover compositing, honours `high-quality-images` | missing |
| `cartridges/store/managers/steam_api_manager.py` | `lib/cartridges/store/managers/steam_api_manager.rb` | developer metadata | missing |
| `cartridges/store/managers/sgdb_manager.py` | `lib/cartridges/store/managers/sgdb_manager.rb` | SteamGridDB covers; raises "Couldn't Authenticate SteamGridDB" / "Verify your API key in preferences" | missing |
| `cartridges/utils/run_executable.py` | `lib/cartridges/run_executable.rb` | launches games (platform-specific) | missing |
| `cartridges/utils/save_cover.py` | `lib/cartridges/save_cover.rb` | `save_cover`, `convert_cover` | missing |
| `cartridges/utils/steam.py` | `lib/cartridges/steam.rb` | VDF/ACF parsing, Steam API | missing |
| `cartridges/utils/steamgriddb.py` | `lib/cartridges/steamgriddb.rb` | SGDB client | missing |
| `cartridges/utils/rate_limiter.py` | `lib/cartridges/rate_limiter.rb` | Steam API rate limiting, persisted to `steam-limiter-tokens-history` | missing |
| `cartridges/utils/sqlite.py` | `lib/cartridges/sqlite.rb` | SQLite reads (Lutris) | missing |
| `cartridges/shared.py.in` | `lib/cartridges/shared.rb` | `AppState`, `APP_ID`, `PREFIX`, the two `Gio::Settings`, every XDG/host/flatpak path, `games_dir`, `covers_dir` | missing |
| `cartridges/logging/setup.py`, `color_log_formatter.py`, `session_file_handler.py` | `lib/cartridges/logging/*.rb` | logging; the session log files are what the About dialog's debug info is made of | missing |
| `search-provider/cartridges-search-provider.in` | `lib/cartridges/shell_search_provider.rb` | GNOME Shell search provider over D-Bus (`…SearchProvider.ini` + `.service`) | missing |

---

## 16. Data, settings and translations

| Upstream | → | Kind | Present |
|---|---|---|---|
| `data/page.kramo.Cartridges.gschema.xml.in` | `lib/cartridges/settings.rb` + an installed schema | settings — 2 schemas, 42 keys (36 app + 6 `.State`: `width`, `height`, `is-maximized`, `sort-mode`, `show-sidebar`, `steam-limiter-tokens-history`) | missing |
| `data/gtk/style.css` | `lib/cartridges/style.css` (loaded via `Gtk::CssProvider`) | stylesheet — `--accent-color`/`--accent-bg-color` purple overrides (light + dark), `.no-hover > flowboxchild:hover`, `#details_view`, `#details_view_play_button` | missing |
| `data/gtk/style-dark.css` | folded into the above | stylesheet — legacy dark variant, duplicated by the `@media` block in `style.css` | missing |
| `data/cartridges.gresource.xml.in` | resource loading in `lib/cartridges.rb` | resources — 5 `.ui`, metainfo, `style.css`, 2 placeholder SVGs, 8 source icons under `/icons/scalable/categories/` | missing |
| `data/library_placeholder.svg`, `library_placeholder_small.svg` | `data/` in the port | asset — the no-cover placeholders, loaded as `Gdk::Texture`s by §6 | missing |
| `data/icons/sources/*.svg` (8) | `data/icons/sources/` | asset — sidebar and preferences source icons | missing |
| `data/icons/hicolor/**` (4) | `data/icons/` | asset — app icon, symbolic + devel variants; the symbolic one is `notice_empty`'s icon | missing |
| `data/page.kramo.Cartridges.desktop.in` | `data/` | desktop entry (translated) | missing |
| `data/page.kramo.Cartridges.metainfo.xml.in` | `data/` | metainfo — **read at runtime** by `Adw::AboutDialog.new_from_appdata` | missing |
| `po/` (38 locales + `cartridges.pot`, `LINGUAS`, `POTFILES`) | `po/` | i18n — gettext plus `ngettext` for the import summary | missing |

---

## Blockers and open questions

1. **No PIL.** `game_cover.py` (blur, luminance stats), `cover_manager.py`
   (compositing) and `save_cover.py` (animated-GIF detection, format
   conversion) all lean on PIL. Needs a GdkPixbuf/Cairo or `ruby-vips` route,
   and the luminance formula reproduced exactly or §3b's backdrop drifts.
2. **No blueprint, by design.** All five `.blp` trees have to be rebuilt as
   memoized Ruby widget methods, including things blueprint gives for free:
   `Adw::Breakpoint` with 13 setters, two `bind … inverted` /
   `bind … bidirectional` property bindings, `accessibility { labelled-by }`,
   and the `menu`/`section`/`submenu`/`item` models (which become
   `Gio::Menu` built by hand). Confirm against the `ruby-gtk` skill that
   `Adwaita::Breakpoint` and `Gtk::Expression`-based bindings are usable from
   the bindings before committing to a shape for §2.
3. **Adwaita version floor.** `Adw::ShortcutsDialog`, `Adw::ShortcutsSection`,
   `Adw::ShortcutsItem`, `Adw::ButtonRow`, `Adw::Spinner` and
   `Adw::PreferencesGroup#separate-rows` are libadwaita 1.6–1.8 API. The dev
   shell's libadwaita needs checking before §8 and §9 are planned.
4. **GResource.** The port has no `.gresource`; the placeholder SVGs, source
   icons, `style.css` and the metainfo are all loaded by resource path upstream.
   Decide early whether the port compiles a resource bundle or loads from
   `data/` on disk — §6, §4 and the About dialog all depend on the answer.
5. **Threads.** Upstream runs source scans on `Gio::Task.run_in_thread` and
   cover conversion on `GLib::Thread.new`, with progress polled on a 100 ms
   `GLib.timeout_add`. The Ruby bindings' GVL behaviour here needs a spike
   before §10.
6. **ngettext.** The import summary toast needs plural forms, not just
   `gettext`.
7. **`Adw::AboutDialog.new_from_appdata`** reads the installed metainfo XML at a
   resource path. If the port does not ship one, the About dialog has to be
   built field by field instead.
8. **Namespacing.** `lib/cartridges/application.rb` nests under
   `module Cartridges`, whereas the pilot port is flat `lib/*.rb`. This
   inventory follows what already exists here; worth confirming before the
   first real file lands.
