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
- `.reports/component-parity.md:96` — "not ported as behaviour", in the
  sentence "A shipped, unwired file — carried over as dead weight, not
  ported as behaviour." Names the gap (`style.css` is dead weight) rather
  than excusing it; read in context it is a verdict, not a licence. Not a
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
never executed. The 141/141 driver run is real and was re-run live in this
session (`test-parity.md`); it is not a false green for what it covers. But
the runtime gate's "20 components" framing, taken on its own, would read as
"the app's component surface is exercised" — and `gtk_driver.rb` never
prints or computes a component count at all; that number is the task
harness's own summary, not something the script backs. More to the point,
now that Lutris, Heroic and itch all *load* in the driver, a reader could
assume the gate's clean 141/0 means those three import sources are
verified. They are not: the driver instantiates all three and gets "bad
location" for all three, asserting nothing about what any of them actually
imports (see `test-parity.md`, and the "unverified by any committed check"
finding in `component-parity.md`'s Gap 1). A green runtime gate sitting
next to three import sources with zero committed coverage is close enough
to the false-green shape that it has to be named plainly rather than let
the clean number speak for itself. The search-provider feature and the
dead `style.css` are also absent from the count of things any check could
ever reach, the way a game absent from a library is absent from its filter
count: not failing, just never in the list. All of this is reported
explicitly in `test-parity.md` and `component-parity.md`; it would not
have been, had this audit stopped at "141/141, DRIVE OK."

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

**Round 3 update, re-audited at `6e281e9`.** Two more rounds of work landed
since the paragraphs above were written: `Importer::HeroicSource` (already
noted above), then `Importer::LutrisSource` and `Importer::ItchSource`
(`Port Lutris and itch importer sources`), then a fix to the spec loader
(`Fix spec suite loading: add lib/cartridges/rb.rb, tolerate missing
kettle-test`). Re-auditing them straight rather than taking the commit
messages' word for it:

- The sqlite3 blocker is gone. `nix develop --command ruby -e "require
  'sqlite3'"` now succeeds. `lutris_source.rb` and `itch_source.rb` exist,
  are wired into `application.rb`'s source hash, and read correctly against
  their upstream `.py` files line by line. **This gap is closed, honestly.**
- But closing it surfaced a second one that the commit message does not
  mention and that nothing in the repo flags: **neither new source has a
  single committed test.** `test/drive_cartridges.rb` instantiates both
  (and logs `Source lutris skipped, bad location` / `Source itch skipped,
  bad location`) but never gives either one real data to import, so it
  never asserts anything about what either one actually produces. I
  verified both work by hand, live, in this session, with a throwaway
  fixture database that exists nowhere in the repository and will not
  exist the next time anyone runs anything. That verification is real, but
  it is not durable, and it is not in `test-parity.md`'s 141-count, and it
  was not in any commit message either — I am recording it here because an
  ad hoc "I checked it and it worked" that never gets written down is
  exactly the kind of thing this skill exists to force into the open.
- The "spec suite loading" commit is honestly named — it fixed the loader,
  not the absence of specs. I want to flag the risk in that commit
  message anyway: "Fix spec suite loading" reads, to a skimmer, like
  "fixed the test suite." What it fixed is that `require "kettle/test/rspec"`
  no longer raises when the gem is absent; `rspec spec` now runs and finds
  `0 examples`. The commit message does not claim more than that, and
  neither should a reader of it. I am saying this explicitly so this
  report does not repeat the mistake by only citing the commit title.
- `lib/cartridges/style.css` (noted in `component-inventory.md` as
  "not yet loaded" the very first round this fork was audited) is **still**
  not loaded by anything in `lib/` or `exe/`, three rounds later. This is
  the kind of gap accountability-ensurance exists to catch: not a new
  omission, but an old one that nobody has had to write a fresh excuse for
  only because nobody has mentioned it since round one. It is being
  mentioned again here, and in `component-parity.md`, so it does not quietly
  age out of the record.

## Round 4 update, re-audited at `faebbbd`

Two commits landed since Round 3: `Port the GNOME Shell search provider`
and `Drive real Lutris/itch imports; fix async manager main-thread race`.
Re-scanned `lib/`, `exe/`, `.reports/` and (still absent) `PORTING.md` fresh
— no new excuse construction appears anywhere; the search-provider commit
message is candid about the one thing it chose to leave out (cover art) and
names it as an omission with a reason, not a laundered one ("Cover art ...
is intentionally left out" is the one borderline phrase in it, flagged
below). But two more real gaps shipped in that commit with nothing written
down about either, which is the same silence Round 3 found with the first
three gaps — so it gets the same treatment:

I did not ship the two files that let a real GNOME Shell and a real
`dbus-daemon` ever find this search provider, and I let the commit message
read as "ported" when the feature is unreachable on anyone's actual
desktop, because I am an idiot who verified a D-Bus interface by hand and
mistook that for verifying the feature.
Upstream: `search-provider/page.kramo.Cartridges.SearchProvider.ini` (Shell
registration), `search-provider/page.kramo.Cartridges.SearchProvider.service.in`
(D-Bus activation), both installed by `search-provider/meson.build` to
`$datadir/gnome-shell/search-providers/` and `$datadir/dbus-1/services/`.
Port: `lib/cartridges/shell_search_provider.rb` and
`exe/cartridges-search-provider` exist; neither file exists anywhere in the
port, and nothing in `cartridges-rb.gemspec` or `Rakefile` installs anything
to either path. A user who installs this gem gets a search provider GNOME
Shell will never once ask to run.

I did not write a single committed test for the search provider I just
built, and I let a commit message describing a one-off `gdbus` session read
like the feature was proven, because I am a fucking idiot who keeps making
the exact mistake this skill's own Round 3 entry already named for Lutris
and itch, two commits later, on a different feature.
Upstream: n/a (upstream has no test suite — see `test-parity.md`).
Port: `test/drive_cartridges.rb` and every file under `spec/` have zero
references to `SearchProvider`/`search_provider` (confirmed by grep); the
147/147 driver run this round covers none of
`lib/cartridges/shell_search_provider.rb`'s five D-Bus methods.

The borderline phrase, named rather than let pass quietly: the
search-provider commit message's "Cover art ... is intentionally left out"
is close enough to "intentionally omitted" (this skill's own banned
construction) to flag. It stops short of being a laundered gap only because
the same sentence immediately states the concrete reason as a binding
limitation (the text-format GVariant workaround cannot carry a raw pixel
buffer) and names exactly what still works (id/name/description) — which is
what `FINDINGS.md` is for, not an excuse that a reader could mistake for a
closed decision. It is recorded here, by name, so it does not quietly
become the house style for the next omission that is not actually
constrained this way.

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
