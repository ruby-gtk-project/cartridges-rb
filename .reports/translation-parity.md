# Translation parity — cartridges-rb

Re-run this round (port now at `ruby` @ `faebbbd`: a search-provider port and
a real-fixture/concurrency-fix commit have landed since the last pass).
Every finding below was re-verified live and is unchanged: no `po/`
directory, no `.pot`, no gettext call, in a tree that now has one more Ruby
file than it did last round (`lib/cartridges/shell_search_provider.rb`).
That file was read directly and carries no user-visible string of its own —
every value it marshals (game id, name, developer) is data read off disk,
not UI text — so it opens zero new translation rows and closes none either.
The 148/148 gap count from the previous round is unchanged.

| | |
|---|---|
| Upstream | `origin/main` @ `c4454fd` |
| Port | `ruby` @ `2cb65fe` |
| Upstream msgids | 148 (`po/cartridges.pot`, 149 `^msgid` lines minus the empty header entry) |
| Upstream languages | 38 (`po/LINGUAS`: ar, be, ca, cs, de, el, en_GB, es, eu, fa, fi, fr, hi, hr, hu, ia, ie, it, ja, ka, kk, ko, kw, nb_NO, nl, nn, pl, pt, pt_BR, ro, ru, sv, ta, te, tr, uk, vi, zh_Hans) |
| Port msgids | **0** |
| Port languages | **0** |
| Gaps | **148** |

## The key sets are not equal — none at all

```
$ find . -name '*.po' -not -path './.git/*'            # (no output)
$ find . -iname '*.pot' -not -path './.git/*'           # (no output)
$ ls po 2>&1
ls: cannot access 'po': No such file or directory
$ grep -rln "gettext\|FastGettext\|require.*i18n" lib    # (no output)
$ grep -rc '_("' lib/cartridges/*.rb | awk -F: '$2>0'    # (no output — every file is 0)
```

There is no `po/` directory in the port, no `.pot`, no `gettext`/`FastGettext`
require anywhere under `lib/`, and `grep -c '_("'` is **zero in every one of
the 28 files under `lib/cartridges/`**, including `preferences_dialog.rb`,
`window.rb`, `details_dialog.rb`, `shortcuts_dialog.rb` and
`application.rb`, which between them carry the bulk of upstream's
user-visible strings (menu items, button labels, dialog headings, error
messages, the whole Preferences page, every accelerator's shortcuts-dialog
description).

Every user-visible string in the port is a bare English literal:

```ruby
# lib/cartridges/importer/importer.rb
dialog.heading = "Warning"
dialog.add_response("close", "Dismiss")
...
"The following errors occured during import:"
```

```ruby
# lib/cartridges/preferences_dialog.rb
@sgdb_enabled_row ||= Adwaita::SwitchRow.new.tap { |row| row.title = "Download Covers From SteamGridDB" }
```

None of this is marked, so none of it produces a catalogue entry, so none of
upstream's 38 languages' translations of these strings (or any others) can
ever apply. This is translated into English only, for the entire app,
without exception.

## Each key byte-identical — not applicable, there are no keys to compare

Step 2 of the skill (byte-for-byte diff of each msgid) cannot run because the
port side of the diff is empty. Flagging this explicitly rather than
reporting "0 reworded, 0 unmarked" — that phrasing would read as a pass. It
is not a pass; it is 148 keys that were never attempted.

## The languages come with it — no

`po/LINGUAS` and the 38 `.po` files are not present anywhere in the `ruby`
branch, and the port's `Gemfile`/`gemspec`/`Rakefile`/`flake.nix` compile no
`.mo` and reference no locale directory. There is no mechanism in the port
by which a non-English speaker would ever see anything but English, however
complete the catalogue eventually becomes, because nothing loads a catalogue
at all (no `GetText.bindtextdomain`, no `FastGettext.text_domain=`, no
`I18n.load_path` — confirmed absent by the same greps above).

## One honest mitigating note, not a defense

`.reports/component-inventory.md` — written before any port code existed —
already flagged this exact gap (`po/` row: "missing — no `po/` directory in
the port") and listed `ngettext` for the import summary as a named blocker.
So this is not a silently-discovered regression; it was a known, written-down
risk from the start of the project. It has simply never been closed, and
nothing written since (no commit message, no comment, no later report)
revisits it. See `accountability-ensurance.md`.

## Conclusion

148/148 gaps. Translation parity does not partially hold for this port; it
does not hold at all. Every string in every window, dialog, menu and error
path would need to be re-authored behind a translation marker with
upstream's exact bytes, and upstream's full `po/` tree (38 languages) would
need to ship with the port, before this ledger has a single `ported` row.

## Round 5 update, re-audited at `2cb65fe`

`Wire style.css, search-provider data files, and Heroic/shell-provider test
coverage` landed since the last pass. Re-ran every check above live: no
`po/`, no `.pot`, no gettext call, still 0 port msgids. The two new data
files this commit ships
(`data/page.kramo.Cartridges.SearchProvider.ini`,
`data/page.kramo.Cartridges.SearchProvider.service.in`) were read directly
— both are plain key=value config (`DesktopId=`, `BusName=`, `Exec=`), with
no user-facing string and no counterpart in upstream's `.pot` either, so
they open zero new rows on either side. The 148/148 gap count, and every
finding above, is unchanged.
