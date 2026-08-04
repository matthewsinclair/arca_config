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
