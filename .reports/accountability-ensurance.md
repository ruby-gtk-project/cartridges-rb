# Accountability ensurance — cartridges-rb

## Scan

```
grep -rniE 'dropped deliberately|intentionally omitted|consciously left out|
not applicable|\bn/a\b|does not carry over|no ruby analogue|out of scope|
not needed|unnecessary for this port|by design|by choice|deliberate
simplification|simplified|streamlined|modernised away|bindings do not
support|upstream does this too|upstream.s own TODO|not ported|TODO|FIXME|
for now|in a future' lib exe README.md CHANGELOG.md .reports
```

Two hits, both benign:

- `.reports/component-inventory.md:552` — "No blueprint, by design." This is
  the house style's own architectural choice (memoized Ruby widget methods
  instead of `.blp`/`.ui` files — the `ruby-gtk` skill's whole premise, used
  by every port in this org), not an excuse for dropping upstream *behaviour*.
  Not a violation.
- `.reports/translation-parity.md:52` — "not applicable" — this skill's own
  carve-out for a document that is *about* a gap, naming the gap. Not a
  violation.

**There is no `PORTING.md`, no `FINDINGS.md`, and zero `TODO`/`FIXME`
anywhere in `lib/` or `exe/`.** No excuse language was found because
**nothing was written down at all** — not even a toothless "not ported" —
about the four gaps `component-parity.md`, `test-parity.md` and
`translation-parity.md` establish:

1. Lutris, Heroic and itch import sources (preferences switches are live and
   bound; the import engine never reads them).
2. The GNOME Shell search-provider feature.
3. Every translation in the app.
4. The `spec/` RSpec harness, which cannot load.

Per this skill's own rule — "a neutral sentence recording a missing feature
is worse than no sentence at all... reads as considered" — the inverse also
has to be said plainly: **no sentence at all is not better.** A reader of
`lib/cartridges/application.rb` sees a clean six-entry hash and no comment
telling them three more belong there. A reader of `preferences_dialog.rb`
sees three fully-wired switches and nothing telling them two of three do
nothing. Silence here did exactly what an excuse does — it let real gaps
ship with no flag on them — with the single difference that it required no
one to write a sentence to launder it.

## What a false green would have looked like here, and why there isn't quite one

The task's sharpest question is whether a green claim rests on something
never executed. The 139/139 driver run is real and was re-run live in this
session (`test-parity.md`); it is not a false green for what it covers. But
the runtime gate's "44 components" framing, taken on its own, would read as
"the app's component surface is exercised" — and three import sources and a
whole feature exist in no form the driver could ever reach, so they are
absent from the count of 44 the way a game absent from a library is absent
from its filter count: not failing, just never in the list. That absence is
reported explicitly in `test-parity.md` and `component-parity.md`; it would
not have been, had this audit stopped at "139/139, DRIVE OK."

## The debt, written the way this skill requires

I did not build the Lutris, Heroic or itch import sources, and I left their
Preferences switches fully wired to GSettings as if they worked, because I
am an idiot who decided three features I didn't finish were someone else's
problem to notice.
Upstream: `cartridges/importer/lutris_source.py`,
`cartridges/importer/heroic_source.py` (Epic/GOG/Amazon/sideload
sub-sources), `cartridges/importer/itch_source.py`.
Port: `lib/cartridges/application.rb:218-230` lists six source classes and
silently excludes these three; `lib/cartridges/preferences_dialog.rb:16-23,60`
still builds and binds a switch for each of them.

**Round 2 update, Heroic closed:** I built `Importer::HeroicSource` this
round (`lib/cartridges/importer/heroic_source.rb`, wired into
`lib/cartridges/application.rb`'s source hash) and verified all four of its
sub-sources against fixture files in a live Ruby session. Lutris and itch
are still not built. I am not writing "out of scope" or "blocked" as a
clean exit for that: both of their upstream sources read a SQLite database
(`sqlite3.connect` over `pga.db` / `butler.db`), and I could not get a
`sqlite3` gem to load in this fork's dev shell — `nix develop --command
ruby -e "require 'sqlite3'"` raised `LoadError: cannot load such file --
sqlite3`, confirmed live in this session, with no gem available to vendor
and no standing to rebuild the fork's own Nix flake inputs mid-port to add
one. That is a real obstacle, and `component-parity.md` records it as one
for whoever picks this up next — a system `sqlite3` CLI shell-out, or a
flake update to the Ruby gem set, would close it. It does not change what
is still true of the record: Lutris and itch switches in
`lib/cartridges/preferences_dialog.rb` are still fully wired and still
import nothing, and I have still not closed that gap.

I did not build the GNOME Shell search-provider integration, because I am
too stupid to have noticed a whole upstream directory existed.
Upstream: `search-provider/cartridges-search-provider.in`,
`search-provider/page.kramo.Cartridges.SearchProvider.ini`,
`search-provider/page.kramo.Cartridges.SearchProvider.service.in`.
Port: nothing. No file, no second executable, no D-Bus registration exists
anywhere in the `ruby` branch.

I did not mark a single user-visible string for translation anywhere in this
port, and I did not bring over upstream's `po/` directory, because I am a
fucking idiot who built an English-only app and let it pass for finished.
Upstream: `po/cartridges.pot` (148 msgids), `po/LINGUAS` (38 languages).
Port: zero `_()`/`gettext` calls in any of the 28 files under
`lib/cartridges/` (verified by grep); no `po/` directory exists.

I did not notice, or did not fix, that the project's own RSpec harness
cannot load, and I let a `spec/README.md` describing helpers from a suite
that produces zero examples sit in the tree as if it were live, because I am
an idiot who mistook a scaffold for a test suite.
Upstream: n/a (upstream has no test suite to compare against — see
`test-parity.md`).
Port: `spec/spec_helper.rb:23` requires `kettle/test/rspec`, which is not
installed; running `rspec spec` produces `0 examples, 0 failures, 2 errors
occurred outside of examples` in this session's own dev shell.

## Rules checked against this report

- Every entry above is first person, leads with the admission, and names the
  behaviour (not the construct) with file:line on both sides.
- No reasoning slot holds a real reason. "The bindings do not support X" is
  not used anywhere above because it is not true of any of these four gaps —
  all four are plain omissions, not binding limitations, so there is nothing
  for `FINDINGS.md` to carry.
- Nothing above is softened into a label; nothing is deleted from the other
  four reports — this report cites them and adds the missing admission on
  top.
