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

## Settled -- corrections to the arca_cli handover note (permanent record now in design.md + handover-to-vc.md)

- `Arca.Config.get_config_location/0` has **never existed** in arca_config: `git log -S "get_config_location" --all` is empty, and it is absent at both pinned `8b30615` and HEAD. arca_cli hard-matches it at `cli_command_helper.ex:350`. Removed from the blast-radius table; the facade will nonetheless gain the function under AC-02.3.
- The two commits of drift are **mix.lock only**: `git diff --stat 8b30615..HEAD -- lib/ mix.exs` is empty. arca_cli's 710 tests ran against source-identical arca_config.
