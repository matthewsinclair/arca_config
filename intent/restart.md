---
verblock: "04 Aug 2026:v1.0: matts - restart context after ST0002 remediation and the 0.3.0 release"
---

# Restart Context

## Where things stand

**ST0002 remediation is complete and arca_config 0.3.0 is published.** Nothing further can be built in this repository until the downstream verification comes back.

- **`v0.3.0` tagged and pushed** -- the repo's first tag -- at `ccd8fb5`, whose tree is identical to the CI-green build `03969fa`.
- WP-01 through WP-05 all DONE. Contract `intent ac status ST0002` = **35/38 -- BLOCKED**, correctly.
- Suite 222 passed (48 doctests, 174 tests), 8 seeds, zero stray output. CI green on all three matrix cells.

## What the next session should do

**Almost certainly: nothing but wait, or help vc.** The three open ACs are AC-00.1 (vc's ack), AC-00.2 (vc's rebuild of arca_cli) and AC-06.1 (vc's report). None is buildable from here.

If vc reports failures from the arca_cli rebuild, those come back to this repo as fixes -- that is the one path that reopens work. Expect exactly one arca_cli test to fail by design (`error_format_test.exs`, "failure: a setting that does not exist"); the one-line fix belongs in arca_cli and is written out in `CHANGELOG.md`.

## Read in this order

| File | Why |
| --- | --- |
| `intent/wip.md` | The project snapshot: what changed, what is left, the standing lessons |
| `intent/st/ST0002/release-verification.md` | The handover package for vc -- what is outstanding, for whom, and where to attack |
| `intent/whiteboard/cc/wip.md` | This node's live board (paused). Watch-outs matter |
| `intent/st/ST0002/impl.md` | As-built per WP, 15-row changed-tests ledger, public-symbol removal log |
| `intent/st/ST0002/acceptance.md` | The 38-AC contract with live AT status |
| `intent/st/ST0002/design.md` | 40-finding ledger, 5 archetypes, all 7 rulings, the ratified notification matrix |
| `CHANGELOG.md` | Consumer-facing migration notes for 0.3.0 |

## Things that will bite a session that does not know them

- **Do not delete `Arca.Config.register_change_callback/2`.** Zero callers here and zero in arca_cli; `arca_cli.ex:129` only asks whether it exists via `function_exported?/2`. Deleting it silently stops every `save_settings` downstream. Pinned by `test/config/consumer_contract_test.exs`.
- **In a library, a public function with no in-repo callers is untested contract surface, not dead code.** No public symbol was retired in this whole thread; the two that looked deletable became delegates.
- **`mix compile --warnings-as-errors` does not see test files.** Use `mix test --warnings-as-errors`.
- **`test_helper.exs` fails the run** if the suite changes the working tree, the config environment variables, or `:arca_config`'s application settings. Do not widen the baseline to silence it.
- **Suite output is dots only**, enforced by `ExUnit.start(capture_log: true)`. A test that asserts on a log still wraps it in `ExUnit.CaptureLog.capture_log/1`.
- **Coverage threshold is 90 and enforced** (`mix.exs`), currently 90.47%. Test-support modules are excluded because they are not shipped.
- **`Cfg.get/1` reads server state, not the file.** Setting location env vars behind the running server does not redirect reads.

## Decisions deferred, not lost

- `Cfg.inspect_property/1` still reads from disk and reports `{:config, :not_found, [name]}` for a top-level key only. It is documented as not traversing nested paths, so it was out of AC-02.1's scope and stays under AC-05.1's default-KEEP.
- `Cfg.local_config_pathname/0` is a second hand-rolled tier chain that does not go through `first_present/1` and reports no source. Deliberately kept and documented as out of resolution (`impl.md`, AF-25).
- Eight declared dependencies have no in-repo call site and stay under default-KEEP pending downstream evidence. `test/deps_audit_test.exs` names all twelve with the reason each is kept and fails when one changes silently.
- The env-var-name-to-key-path translation in `load_config_phase/0` is domain knowledge with no home of its own; the critic suggested an `Arca.Config.EnvOverrides` in a later thread. Not a gate failure.
