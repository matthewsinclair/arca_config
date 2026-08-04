# cc archive -- 2026-08-04

Archived at localfold. Live board keeps frontmatter, roster, DOING, TODO, watch-outs, and standing decisions; this file holds the settled session record. Append-only; never reloaded on pickup.

## DONE 2026-08-04 (session 797c6bb0)

Session ran in two model phases: Opus (pickup, baseline, full lib read), then Fable (analysis phase, at hv's switch), then Opus again (ratification + fold).

- Pickup as sole node. Baseline: `mix compile --force --warnings-as-errors` clean; `mix test` 128 passed (41 doctests, 87 tests), 1.4s. HEAD 9925115.
- Opus pre-read of all 9 lib modules produced 23 findings; sealed rather than briefed once the arca_cli handover established that analysis belonged to Fable. Preserved at `intent/st/ST0002/preread-sealed.md`.
- Fable analysis phase: 39-finding ledger in 5 archetypes, all evidence file:line, 6 findings executed by probe. Scripts + verbatim output preserved at `intent/st/ST0002/probes/`.
- Headline executions: AF-01 put on a read-only file logs `:eacces`, returns `{:ok, "v"}`, serves the phantom from memory. AF-26 domain heuristic resolves to `:elixir_uuid`, an unused dep. AF-25 a put with no pre-existing target was redirected into the repo root by the location existence-flip. AF-17 notification matrix incoherent -- per-key subscribers never fire on external changes. AF-23 README documents precedence backwards, the root cause of arca_cli A22.
- Provenance disclosed rather than claimed: the model switch happened in-session, so the sealed set was in Fable's context. Ran as verification-plus-extension, not cold. 21 of 23 sealed confirmed (4 executed), 2 softened, 16 Fable-new. The "independently rediscovered" claim is not made anywhere.
- Probe-attribution self-correction on the record: the first P3 run demonstrated AF-25 (location flip), not AF-01; P3b pinned resolution and executed AF-01 properly. Both in the ledger with honest attribution.
- ST0002 elaborated end to end: info.md objective/context, design.md, acceptance.md (36 ACs), tasks.md, impl.md with changed-tests + symbol-removal ledgers stubbed. WP-01..06 created via `intent wp new`, briefs filled. `intent todo update` run.
- `intent/wip.md` rewritten from a stale March-2025 changelog into a live project snapshot.
- `handover-to-vc.md` written: self-contained verification package for the arca_cli session, carried by hv across the repo boundary.
- hv ratified the contract and decided R1/R2/R4/R5/R6/R7. R3 (escript CLI: extract vs delete) left open.
- Probe fallout cleaned (`.arca_config/ro.json` removed). The 4 pre-existing committed `.arca_config/` artifacts left for WP-05.

## DONE 2026-08-04, second half (same session, post-compact): WP-01, WP-03, WP-04

Three work packages built, each red-first, each committed behind compile + suite gates. Contract 0/38 -> 19/38. Suite 128 -> 152 green. As-built for all three is in `intent/st/ST0002/impl.md`; this is the session record.

- **WP-01 truthful returns (AR-1)**, commit `e82dfbc`, gate 6/6. Write failures propagate instead of being logged and discarded; `write_file_with_logging/2`, whose failure branch returned `Logger.error/1`'s `:ok`, is gone. Cache unavailability is distinct from key-miss. enoent reads as an empty config only for the documented bootstrap caller (R4).
- **WP-03 notification + watcher coherence (AR-3)**, commit `c66bd29`, gate 6/6. One matrix, three channels, five paths, each firing once. The watcher survives an unparseable file instead of restarting into silent dormancy. The write-suppression window is removed rather than patched, so no external edit can be lost in it. Cache coherence on ancestors.
- **WP-04 location model (AR-4)**, commit `8d82cf4`, gate 7/7. The domain heuristic and the file-existence flip are both gone; the README's backwards precedence -- root cause of arca_cli's A22 -- is corrected and now matches the moduledoc and a test line for line; `config/.env` treats its lines as defaults so a shell export wins; and the suite proves its own isolation via a baseline + after-suite drift check.

Three corrections I made to my own work, on the record because each was the same class of error:

- **WP-01**: nothing. The error was earlier, in AC-05.1 (see the first fold).
- **WP-03**: I justified widening the notification matrix partly on "arca_cli registers zero callbacks". That is hv's overruled inference one step removed -- an unknown consumer may register one, and the widening made a callback that writes config reachable on the put path for the first time. Two protections added and pinned by test: callbacks dispatch off the server process, and a write that changes nothing raises no event.
- **WP-03 again**: I then had to *narrow* a rule I preferred. Applying no-change-no-event uniformly broke two tests asserting a bare `reload/0` notifies. Those tests are the only written record of that contract, so the rule was scoped to writes and `reload_external/0` added for the watcher. Rewriting the tests to suit the implementation would have been the same move as deleting a dependency because nothing local calls it.
- **WP-04**: a green suite across six consecutive seeds was still hiding a leak, because the previous run's residue was masking it. Only the before/after comparison found it. Seed sweeps prove order-independence, not isolation.

Answered vc's privately-held lens without having been told it: all 11 test modules now carry a per-module `async: false` reason naming the global state they touch, which is exactly the "answered per module, not in bulk" standard vc set. All 11 stay sync -- the location model is process-global, which is AR-4's own finding rather than something WP-04 could remove.

## Settled -- corrections to the arca_cli handover note (permanent record now in design.md + handover-to-vc.md)

- `Arca.Config.get_config_location/0` has **never existed** in arca_config: `git log -S "get_config_location" --all` is empty, and it is absent at both pinned `8b30615` and HEAD. arca_cli hard-matches it at `cli_command_helper.ex:350`. Removed from the blast-radius table; the facade will nonetheless gain the function under AC-02.3.
- The two commits of drift are **mix.lock only**: `git diff --stat 8b30615..HEAD -- lib/ mix.exs` is empty. arca_cli's 710 tests ran against source-identical arca_config.

## DONE 2026-08-04, third part (same session, post-compact): WP-02, WP-05, AC-02.2, critic pass, release

The remediation finished. Contract 19/38 -> 34/38, suite 152 -> 222 green, and arca_config 0.3.0 is published. Commits `afcff58`, `b0b63ab`, `f3aad5f`, `284a803`, `7b00d31`, `5978840`, `5cc2598`, `dca58eb`, `a97f3a7`, `27620e9`, `5dbd8da`, `00db498`, `03969fa`.

hv ruled three times on resume, and delegated a fourth: the notification matrix RATIFIED as implemented; AC-00.4 ACCEPTED; **R3 = extract** (CLI to `Arca.Config.CLI`, single Optimus dispatch, escript target dropped, `mix arca.config` and `optimus` kept); and R1's wire format **delegated to me** ("pick a sensible one").

- **AT-00.1 consumer contract + AC-02.3.** Every call arca_cli makes, each assertion citing the arca_cli `file:line`. The `register_change_callback/2` liveness proxy became a test, so deleting it now fails our suite instead of silently stopping every `save_settings` downstream. `get_config_location/0` implemented -- and the handover's claim that arca_cli hard-matches it was **wrong**: line 350 is inside a `@doc` heredoc and never raised. Corrected on the record.
- **WP-02 (AR-2) DONE**, gate 5/5. `Cfg.get/put` delegate to `Server`, which answers AF-37: `Cfg` was never one module. It is the location and load authority, pure over environment and filesystem; the nested get/put half was the duplicate. Kept as delegates, not deleted, per hv's lens. `Access.pop` deletes. The dead `{:ok, conf}` clause and the test that mocked `GenServer` to reach it are gone. AC-02.2 unified the dialect to `{:error, {:config, reason, detail}}`, arca_config first.
- **WP-05 (AR-5) DONE**, gate 6/6. CLI extracted with a single Optimus dispatch (the spec was unreachable before), escript target dropped, both test backdoors removed, one CI workflow, committed `.arca_config/` artifacts and debug scripts gone, dependency set made deliberate rather than pruned.
- **Critic pass (AC-05.6), authorised by hv: 21 findings at the gate, all closed.** It caught a `Protocol.UndefinedError` I had shipped an hour earlier on every error path, and **four criticals the Fable audit missed** -- including C1, data loss: `read_current_config/1` swallowed read and decode failures and ran immediately before overwriting the file.
- **Published.** 0.3.0 pushed to GitHub. CI failed on first run and everything it found was mine: an unenforced coverage gate (the old workflow ran `mix test --cover || true`), test-file warnings nothing checked, and two rounds of stray log output. All fixed; CI green on all three cells.

Five corrections to my own work this part, each on the record because the pattern matters more than the instance:

- **I shipped a bug and the critic found it, not me.** AC-02.2 changed reasons to tuples; five sites still interpolated them into strings. The suite stayed green because nothing exercised a CLI error path and the one `Map` failure test mocked `Server.put` to return a *binary* -- the mock kept the test passing through the exact contract change it existed to cover.
- **I nearly lowered a bar instead of meeting it.** Faced with a failing coverage gate I first set `threshold: 85`. The real gap was `Mix.Tasks.Arca.Config` at 0% -- the CLI path ruling R3 kept *because* it is the documented one. Testing it honestly reached 90.47%, so the threshold stayed at 90.
- **An over-broad find-and-replace shipped three compile warnings** in `callback_test.exs`, and `mix compile --warnings-as-errors` could not see them because it only compiles `lib/`. The gate I had run all thread was blind to test code.
- **I leaked log output twice** after hv's standing rule, and chasing leaks individually did not hold. `ExUnit.start(capture_log: true)` makes dots-only structural.
- **The second leak was also a real defect.** My own C3 warning fired whenever a stat failed, but the watcher re-resolves its path every tick, so a test restoring env vars moved it -- reporting a file "no longer readable" that nobody had said was there. A location change is not a disappearance.

## Settled decisions, retired from the live board

- (2026-08-04) R1 shape decided by hv, wire format delegated to cc and shipped: `{:error, {:config, reason, detail}}`, arca_config first, because 0.3.0 is breaking under R5 and the WP-06 rebuild is the gate that closes the window.
- (2026-08-04) R3 decided **extract**. The audit leaned delete, but `mix arca.config` -- not the escript -- is the documented path, and extract fixes AF-11 and AF-34 without removing surface a user outside the fleet could be invoking.
- (2026-08-04) AT-05.3 restated rather than built as drafted: a gate asserting declared == referenced deps would encode hv's overruled inference as CI and contradict AC-05.1 as rewritten.
- (2026-08-04) AT-05.1 and part of AC-05.6 are structural tests that read source. With a backdoor clause gone, the old message matches no `handle_info/2` and kills the process, so a behavioural test would have to assert a crash.
- (2026-08-04) `Cache` and `remove_callback/1` deliberately keep `{:error, :not_found}` through the dialect unification. Cache's "not found" means *not cached*, and the layer reading the cache first is the one that must tell those apart.

## Release closed out, 2026-08-04 20:57

- **`v0.3.0` tagged and pushed** at hv's instruction -- the first tag this repository has ever had. Annotated, pointing at `ccd8fb5`. Tagged that rather than `03969fa` after diffing `lib`, `test`, `mix.exs`, `mix.lock` and `.github` to confirm the trees are identical: everything between them is documentation, and a tag should mark the code CI actually verified.
- **AC-06.3 satisfied. Contract 35/38.** The remaining three -- AC-00.1, AC-00.2, AC-06.1 -- are one piece of work with three outputs, all vc's.
- `info.md` corrected: it still carried a duplicated "Related Steel Threads" section (populated plus untouched template placeholder) and a "v0.1: Initial version" verblock after the entire thread had run.
- Node held for the day at hv's instruction. Handover to vc is `intent/st/ST0002/release-verification.md`.
