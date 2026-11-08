# Test parity — cartridges-rb

| | |
|---|---|
| Upstream | `origin/main` @ `c4454fd` |
| Port | `ruby` @ `faebbbd` |
| Upstream tests | 0 |
| Ported | 0 |
| Gaps | 0 |

Upstream has no test suite (verified again this round):
`git ls-tree -r --name-only origin/main` has no `test`/`tests` path at all,
`meson.build` and `meson_options.txt` declare no test target, and there is no
`pytest.ini`/`unittest` usage anywhere in the tree. Parity is 0/0 and is met
trivially. **The port therefore inherits no safety net** — every check below
was written for the port and pins nothing upstream considered worth pinning.

## Extra

- `test/drive_cartridges.rb` (+ `test/gtk_driver.rb` harness) — a headless UI
  driver. Run live in this session:

  ```
  $ nix develop --command xvfb-run -a ruby test/drive_cartridges.rb
  ...
  141 of 141 checks passed
  DRIVE OK
  ```

  This matches the runtime gate the task names (141 passed, 0 failed) and is
  a real, currently-passing run, not asserted from memory. **But the gate's
  own "20 components" framing is not something the driver itself asserts** —
  `gtk_driver.rb` prints `"<n> of <n> checks passed"` and `DRIVE OK`/`DRIVE
  FAILED`; it never counts or names "components." Treat that count as the
  harness's own summary, not as a claim the script backs, and read the
  transcript's 43 numbered `d.step` scenarios instead (window startup,
  add/edit validation, library tiles, filtering, search, sort, menus, hover
  reveals, the details page, preferences bindings, shortcuts/accelerators,
  the About dialog, an import run, persistence-to-disk, window close) to see
  what was actually exercised.

  **The driver's import-source coverage is still narrow, and it narrowed in
  a specific, misleading way this round.** The transcript's own log lines
  show all seven source classes present and *skipped for a bad location*:
  `Source steam skipped, bad location`, `... bottles ...`, `... retroarch
  ...`, `... legendary ...`, `... heroic ...`, `... lutris ...`, `... itch
  ...`. That is a real improvement over the previous round (Lutris and itch
  now at least load, construct and get asked to import, where before they
  did not exist) — but "skipped, bad location" means the driver never feeds
  any of the seven sources real data. Nothing in `test/drive_cartridges.rb`
  builds a fixture `pga.db`, `butler.db`, `library.json`, `libraryplay.db`,
  or `.desktop`/retroarch directory and points a source at it. The one
  per-source assertion the driver makes about the three newest sources is
  `d.check("Heroic was added as an import source (schema default is on)")`
  — a check that the source is *listed*, not that importing through it
  produces a game. Lutris and itch get no assertion of either kind. **A
  component that loads is not a component a check exercises**, and by the
  task's own framing that makes `LutrisSource`, `ItchSource` and, to a
  lesser extent, `HeroicSource` unverified by anything committed to the
  repository, regardless of how clean their code reads.

  To close the gap this report flagged above, I built and ran, outside the
  repo's own suite, a throwaway fixture against `LutrisSource` and
  `ItchSource` directly (a synthetic `pga.db`/`butler.db` under
  `XDG_DATA_HOME`/`XDG_CONFIG_HOME`, loaded through `require "cartridges"`
  under `xvfb-run`): `LutrisSource.new.to_a` correctly produced one
  `GameModel` (`name=My Game source=lutris_wine game_id=lutris_wine_1
  exe=xdg-open lutris:rungameid/1`) from a one-row fixture database, and the
  SQL/field mapping in `ItchSourceIterable` reads identically to upstream's
  `ItchSourceIterable.__iter__`. **This confirms the Ruby is correct, but it
  is a one-off ad hoc session check, not a test, and it is not in the
  repository.** The next person to touch `lutris_source.rb` has no
  regression check to run; they have this paragraph, which will rot the
  moment the file changes. That is exactly the gap this skill exists to
  catch: a true "it works" claim that is not backed by anything the
  codebase itself re-runs.

- `spec/` — a generated RSpec harness (`spec/spec_helper.rb`,
  `spec/README.md`). The `lib/cartridges/rb.rb` load-path fix landed this
  round (confirmed by `git log`: "Fix spec suite loading: add
  lib/cartridges/rb.rb, tolerate missing kettle-test"), and the harness now
  *loads* — `kettle/test/rspec` missing no longer raises, it warns and
  continues. Run live in this session, via the devshell's own documented
  command:

  ```
  $ nix develop --command xvfb-run -a ruby -e 'require "rspec/core"; exit \
    RSpec::Core::Runner.run(["--format", "progress", "--require", \
    "spec_helper", "spec"])'
  ...
  NOTE: kettle-test isn't installed; running with plain RSpec.
  No examples found.
  Finished in 0.00562 seconds (files took 6.06 seconds to load)
  0 examples, 0 failures
  ```

  **This is the gap to call out plainly, per the task's instruction: a
  suite that has never been executed — or, now, one that executes and
  finds nothing — is a gap.** `spec/` contains exactly one file,
  `spec_helper.rb`; there are zero `*_spec.rb` files anywhere in the
  directory. The commit that "fixed spec suite loading" fixed the loader,
  not the absence of specs — it made a suite with no tests fail to error
  out instead of erroring out, which is progress on the harness and zero
  progress on coverage. "0 examples, 0 failures" is not a passing suite; it
  is a suite that has never once exercised a line of `lib/`. Nothing in
  `CHANGELOG.md`, `README.md` or the commit message for that change claims
  otherwise, which is correct — but a reader skimming `rake spec` output in
  CI would see "0 failures" and could easily mistake that for green.

## Conclusion

0/0 against upstream is a true parity claim, but it is the weakest kind:
upstream wrote down no behaviour worth pinning, so the port's only
correctness evidence is the 141-check driver, and that driver's coverage of
the three newest import sources (Lutris, itch, and — more weakly — Heroic)
is "constructs without crashing," not "imports a game correctly." The
RSpec suite contributes zero examples, full stop. By the task's own
framing — "a component no check exercises is unverified, not done" —
`LutrisSource` and `ItchSource` are implemented but not done in this
precise sense, and the gate's 141/0 should not be read as covering them.

## Addendum — real Lutris/itch fixtures, and a real port bug they found

The gap above is closed in the repository now, not just in an ad hoc
session check. `test/drive_cartridges.rb` creates a real `pga.db`
(Lutris) and `butler.db` (itch) under the scratch `XDG_DATA_HOME`/
`XDG_CONFIG_HOME` the drive already uses, before `app.import` runs. Both
sources resolve their location against those fixtures instead of hitting
"bad location", and the import step now asserts the actual imported
`GameModel`s: name, `source` (`lutris_wine`, `itch`) and `game_id`
(`lutris_wine_1`, `itch_1`) round-trip exactly as `LutrisSourceIterable`/
`ItchSourceIterable`'s own field mapping says they should. 6 new checks
(2 "source was added", 4 on the imported games), 147 of 147 passing.

Making the fixtures real — so a game pipeline actually runs end to end for
the first time in this driver's history — surfaced a genuine, previously
latent port bug, not a test artifact: `Cartridges::Store::AsyncManager#process_game`
(`lib/cartridges/store/managers/async_manager.rb`) ran its completion
callback directly from the `Thread.new` worker thread. `Pipeline#manager_callback`
calls `advance`, which may run the next *blocking* manager
(`DisplayManager`, which touches live GTK widgets: flow boxes, tiles,
the details page) synchronously on whatever thread called it — so with a
real import, `DisplayManager` could run off the GTK main thread. Upstream's
Python never has this problem: `Gio.Task.run_in_thread`'s completion
callback is delivered back on the thread that created the task (the main
thread) by GTask's own contract; the Ruby port's bare `Thread.new` dropped
that guarantee. It reproduced as exactly the kind of flake a thread race
produces: `nix develop --command xvfb-run -a ruby test/drive_cartridges.rb`
passed clean on the first run after the fixtures were added, then failed
two of the next two with the import dialog never closing and the drive's
own 60s watchdog firing — not a fixture problem, since the three failing
checks were always the same three (dialog closed / import action
re-enabled / no toplevels left), never the new import-content checks.

Fixed by wrapping the callback in `GLib::Idle.add { callback.call(self); false }`,
which is the direct Ruby equivalent of GTask's main-thread delivery.
Re-ran `nix develop --command xvfb-run -a ruby test/drive_cartridges.rb`
five times in a row after the fix: 147/147, `DRIVE OK`, every time — no
flakes, where two of three flaked before. This was a real concurrency bug
in shipped code (any import that actually imports something could hit it,
not just this test), not a binding gap and not a test-only issue, and the
fix changes production code (`lib/cartridges/store/managers/async_manager.rb`),
not the test.

## Addendum 2 — the GNOME Shell search provider has zero committed tests

`lib/cartridges/shell_search_provider.rb` and `exe/cartridges-search-provider`
(added in `Port the GNOME Shell search provider`) are not referenced anywhere
in `test/drive_cartridges.rb` or any other file under `test/` or `spec/` —
confirmed by `grep -rn "SearchProvider\|search_provider\|search-provider"
test/ spec/`, which returns nothing. The 147/147 driver run this round, and
the gate it backs, exercises none of this file's five D-Bus methods, its
game-filtering logic (hidden/blacklisted/removed), or its `search()` matcher.

The commit message for that port says it was verified "against a live
dbus-run-session session bus with gdbus, including special characters,
hidden-game filtering, and the detached subprocess spawn." That verification
is real and specific, but it is the same shape of gap this report's first
addendum found for Lutris/itch before their fixtures landed: **an ad hoc
session check that is not in the repository and will not run again.** The
next change to `search()`'s substring matching, or to `load_games_from_disk`'s
hidden/blacklisted/removed filter, ships with nothing to catch a regression.

Per the task's own framing — "a component no check exercises is unverified,
not done" — the search provider is implemented but not done in this sense,
on top of the packaging gap `component-parity.md`'s Gap 3 records (no
`.service`/`.ini`, so the feature cannot be reached in a real install
regardless of whether its own logic is correct).
