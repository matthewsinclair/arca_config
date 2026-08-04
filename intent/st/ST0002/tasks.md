# Tasks - ST0002: Fable review of arca_config base code

## Tasks

- [x] Baseline: compile --warnings-as-errors clean, mix test 128/128 green, HEAD 9925115
- [x] Fable audit: lib (9 modules), tests (9 files + helper + support), docs, CI, config/, artifacts
- [x] External verification: sibling-fleet probes, arca_cli call-surface, deps tree, git history
- [x] Execution probes P1/P2/P3/P5/P7 (scratchpad/st0002_probes.exs) -- all confirmed
- [x] Triage into 5 archetypes + 39-finding ledger (design.md)
- [x] Draft acceptance contract (acceptance.md, pending hv ratification)
- [x] Cut work packages WP-01..WP-06 (risk-ordered)
- [x] hv: ratify contract (2026-08-04) + rulings R1/R2/R4/R5/R6/R7 decided
- [x] hv: ruling R3 (2026-08-04) -- **extract**: CLI moves to `Arca.Config.CLI`, single Optimus dispatch, escript target dropped, `mix arca.config` and `optimus` kept. WP-05 unblocked
- [x] vc node found + inbox read (3 entries, unread all session -- node postdated pickup); replied 16:40
- [x] Post-ratification corrections: AC-05.1 withdrawn/rewritten per hv's dep ruling; AF-40 + AC-04.7 added from vc's config/.env lead; AF-15 extended with `ansi_enabled:`
- [x] hv: approve AC-00.4 (2026-08-04) -- accepted; contract is 38. AT-00.1 (consumer contract test) is now live work
- [x] R1 error shape (2026-08-04) -- hv delegated the wire format to cc ("pick a sensible one"): `{:error, {:config, reason, detail}}`, arca_config first. vc still has it to verify, but it no longer blocks
- [x] WP-01 Truthful returns (AR-1) -- landed 2026-08-04, gate PASS 6/6; suite 134 green (was 128), deterministic across 8 seeds
- [x] AT-00.1 consumer contract test (AC-00.4) + AC-02.3 facade completion -- landed 2026-08-04; suite 167 green, 5 seeds
- [x] WP-02 One lookup path, one dialect, complete facade (AR-2) -- DONE 2026-08-04, all five ACs green; suite 200 green, 6 seeds
- [x] WP-03 Notification and watcher coherence (AR-3) -- landed 2026-08-04, gate PASS 6/6; suite 147 green, 8 seeds
- [x] hv: ratify the notification matrix in design.md (2026-08-04) -- ratified as implemented, both rules included; AC-03.1 satisfied in full
- [x] WP-04 Location model (AR-4) -- landed 2026-08-04, gate PASS 7/7; suite 152 green, 7 seeds, isolation guard armed
- [x] WP-05 Surface and dependency pruning (AR-5) -- DONE 2026-08-04, all six ACs; critic pass run at hv's instruction, 21 findings all closed; suite 212 green, 7 seeds
- [ ] WP-06 Downstream verification and release (vc + hv)

## Task Notes

Per-WP cycle: red ATs first, implement, green, critic gate, changed-tests flagged in impl.md ledger, commit. No WP starts before the contract is ratified.

Standing since WP-01 (hv, 2026-08-04): suite output is dots only. Production logging that a test provokes deliberately gets captured with `ExUnit.CaptureLog` and asserted, never printed.

## Dependencies

- WP-02 error-shape (R1) and WP-06 rebuild are coordinated with vc (arca_cli session; hv carries traffic).
- R2 (precedence) blocks WP-04; R3 (CLI) blocks WP-05 scope; R4 blocks AC-01.6; R5/R6 block WP-06/WP-05 tail.
- WP-01 lands first: every later WP's error paths build on truthful returns.
