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
- [ ] hv: ruling R3 (escript CLI extract vs delete) -- open, blocks WP-05 scope only
- [x] vc node found + inbox read (3 entries, unread all session -- node postdated pickup); replied 16:40
- [x] Post-ratification corrections: AC-05.1 withdrawn/rewritten per hv's dep ruling; AF-40 + AC-04.7 added from vc's config/.env lead; AF-15 extended with `ansi_enabled:`
- [ ] hv: approve or reject AC-00.4 (proposed scope addition -- pin downstream-relied-upon surface with tests here)
- [ ] vc: concur on the R1 error shape before WP-02 lands (handover-to-vc.md, Ask 1)
- [ ] WP-01 Truthful returns (AR-1)
- [ ] WP-02 One lookup path, one dialect, complete facade (AR-2)
- [ ] WP-03 Notification and watcher coherence (AR-3)
- [ ] WP-04 Location model (AR-4)
- [ ] WP-05 Surface and dependency pruning (AR-5)
- [ ] WP-06 Downstream verification and release (vc + hv)

## Task Notes

Per-WP cycle: red ATs first, implement, green, critic gate, changed-tests flagged in impl.md ledger, commit. No WP starts before the contract is ratified.

## Dependencies

- WP-02 error-shape (R1) and WP-06 rebuild are coordinated with vc (arca_cli session; hv carries traffic).
- R2 (precedence) blocks WP-04; R3 (CLI) blocks WP-05 scope; R4 blocks AC-01.6; R5/R6 block WP-06/WP-05 tail.
- WP-01 lands first: every later WP's error paths build on truthful returns.
