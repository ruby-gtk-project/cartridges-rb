# Test parity — cartridges-rb

| | |
|---|---|
| Upstream | `main` @ `c4454fd` |
| Port | `ruby` @ `fb67b2f` |
| Upstream tests | 0 |
| Ported | 0 |
| Gaps | 0 |

Upstream has no test suite (verified): `git ls-tree -r --name-only origin/main`
has no `test`/`tests` path at all, `meson.build` and `meson_options.txt`
declare no test target, and there is no `pytest.ini`/`unittest` usage anywhere
in the tree. Parity is 0/0 and is met trivially. **The port therefore
inherits no safety net** — every check below was written for the port and
pins nothing upstream considered worth pinning.

## Extra

- `test/drive_cartridges.rb` (+ `test/gtk_driver.rb` harness) — a headless
  UI driver. Census of its `d.check(...)` call sites: **139** checks across
  43 numbered `d.step`/named scenarios (window startup, add/edit validation,
  library tiles, filtering, search, sort, menus, hover reveals, the details
  page, preferences bindings, shortcuts/accelerators, the About dialog, an
  import run, persistence-to-disk, and window close). Run live in this
  session:

  ```
  nix develop --command xvfb-run -a ruby test/drive_cartridges.rb
  ...
  139 of 139 checks passed
  DRIVE OK
  ```

  This is a real, currently-passing run (not asserted from memory) and it
  backs the runtime gate the task names. **But it is narrow, and the
  narrowness matters**: reading the transcript and the source together,
  the driver imports with only Steam, Flatpak, Bottles, Legendary, Desktop
  and RetroArch ("Source bottles skipped, bad location", "Source legendary
  skipped, bad location", "Source steam skipped, bad location", "Source
  retroarch skipped, bad location" — the sandbox's own log lines). It never
  touches Lutris, Heroic or itch (because, per `component-parity.md`, there
  is nothing to touch), never touches the search provider (same reason), and
  never asserts anything about translated strings, locales, or gettext. 44
  "components" having a passing check is a true number; it is not evidence
  that the app's full component surface was exercised, and three import
  sources plus one whole feature were never in scope to be exercised in the
  first place because they do not exist.

- `spec/` — a generated RSpec harness (`spec/spec_helper.rb`,
  `spec/README.md`), scaffolded for the `kettle-test` gem. **It does not
  run.** Confirmed live in this session:

  ```
  nix develop --command ruby -e 'require "rspec/core"; exit RSpec::Core::Runner.run([...])'
  ...
  LoadError: cannot load such file -- kettle/test/rspec
  0 examples, 0 failures, 2 errors occurred outside of examples
  ```

  There are no `*_spec.rb` files in `spec/` at all — only the scaffold's
  `spec_helper.rb` and `README.md`. This is dead, uncallable scaffolding: a
  second "test suite" that contributes zero verified examples and currently
  cannot even load. It is listed here, under Extra, rather than folded into
  the 139 figure precisely so it is not mistaken for coverage it does not
  provide. See `accountability-ensurance.md` — nothing in the repo flags
  that this harness is non-functional.

## Conclusion

0/0 against upstream is a true parity claim, but it is the weakest kind:
upstream wrote down no behaviour worth pinning, so the port's only
correctness evidence is the 139-check driver, and that driver was never
asked to exercise three import sources or the search-provider feature
because neither exists for it to exercise. A component with no test and no
implementation is, by the task's own framing, unverified — not done.
