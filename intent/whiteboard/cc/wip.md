---
node: cc
name: Control Claude
role: control
session_id: 797c6bb0-eb52-4b00-9870-3095616dfef2
heartbeat_at: 2026-08-04T16:33Z
status: paused
focus: "ST0002 -- contract RATIFIED; analysis phase archived; next action is WP-01 (truthful returns)"
claims: [ST0002]
---

# Control Claude (cc)

## Roster (this repo holds only cc)

| Node | Who                              | Where it runs                                                                  |
| ---- | -------------------------------- | ------------------------------------------------------------------------------ |
| hv   | Matthew Sinclair                 | human; adjudicates scope, holds model switches + release                        |
| cc   | this session                     | `arca_config`, node dir `intent/whiteboard/cc/`                                 |
| vc   | session 7a8b32c5, validator      | node dir `intent/whiteboard/vc/` **in this repo** -- one session validates both arca_config and arca_cli, same session_id on both boards |

vc provisioned its node here at 15:59 (`intent claude ws new vc`), after this session's pickup -- so inboxes exist in both directions and are the primary channel. The handover package `intent/st/ST0002/handover-to-vc.md` still travels on its own, because vc reads it from the arca_cli side too.

**Read `inbox.vc.md` at every fold, not only at pickup.** Three vc entries (15:59, 16:05, 16:13) sat unread for the whole session because the node did not exist when pickup ran.

## DOING

- Localfold complete (2026-08-04). Session record archived to `.history/20260804/wip.md`. Paused for compact; the next `/in-session` pickup re-activates this node.
- Replied to vc at 16:40 (`vc/inbox.cc.md`): plan review requested, three seeds dispositioned, retraction acknowledged with my own matching error owned, both vc leads verified (one produced AF-40 + AC-04.7), four asks back. Awaiting vc on the R1 error shape before WP-02.

## TODO (risk order, post-compact)

- **WP-01 truthful returns (AR-1)** -- next action. Red ATs first per acceptance.md AT-01.1..6, then implement. Ruling R4 decided, so AC-01.6 is unblocked.
- WP-02 one lookup path / one dialect / complete facade -- needs vc concurrence on the R1 error shape before it lands.
- WP-03 notification + watcher coherence. WP-04 location model. WP-05 pruning (needs R3). WP-06 vc rebuild of arca_cli (710 tests) + release.
- Per-WP cycle: red-first ATs, implement, green, critic gate, changed-tests flagged in impl.md's ledger, commit.

## Watch-outs

- **Do not delete `register_change_callback/2`.** Zero callers, but `arca_cli.ex:118-130` probes its existence with `function_exported?/2` as a liveness proxy. Delete it and every `save_settings` in arca_cli silently degrades -- no crash, no warning. A call-graph search cannot find this consumer.
- Before retiring **any** public symbol, re-run the fleet probe (AC-00.1). Sibling sweep on 2026-08-04 was clean: `arca_id`, `arca_dbutils`, `arca_notionex`, `arca_doc`, `arca_optimus` have zero `Arca.Config` references.
- arca_cli text-matches our error prose (`arca_cli.ex:1083-1098`). Rewording a not-found message is a silent breaking change to its error dialect until R1 lands on both sides.
- The suite is green and stays green throughout remediation -- it was green across every finding in the ledger. Green is not evidence here; the ATs are.
- Tests that assert a defect get changed, not preserved, and every such change goes in impl.md's changed-tests ledger for vc.
- `Arca.Config.Cfg` is aliased `LegacyCfg` (`server.ex:16`) but is the live loader on every load/reload/switch path and a documented public API with doctests. Resolve ownership in WP-02 (AF-37); do not assume it is dead.

## Decisions

- (2026-08-04) Claimed ST0002 as cc, confirmed by hv.
- (2026-08-04) Breaking changes permitted; the current API need not be preserved.
- (2026-08-04) SUPERSEDED: "no local vc node". vc provisioned one here at 15:59. Verification still sits with the session that also owns arca_cli, so verifier and real acceptance test remain the same node -- but the channel is now inboxes in this repo, not hv carrying every message.
- (2026-08-04) **AC-05.1 withdrawn and rewritten after ratification.** As ratified it inferred dep removability from in-repo non-reference -- the same inference hv overruled vc for. Default is now KEEP; removal needs positive downstream evidence with the WP-06 rebuild as proof. Ratification covered scope, not an invalid inference inside one AC; catching it was mine to do.
- (2026-08-04) Standing lens adopted from hv's retraction ruling: for anything public in a library -- deps, facade functions, exported helpers -- in-repo silence is evidence of *untested contract surface*, not deadness. Remedy is coverage, not deletion. AC-00.4 proposed on that basis.
- (2026-08-04) Analysis ran on Fable as verification-plus-extension, not cold -- the model switch happened in-session, so the Opus pre-read was in context. Disclosed in design.md rather than papered over; the "independently rediscovered" claim is not made.
- (2026-08-04) hv ratified acceptance.md as the completeness boundary. R1 (shape decided, wire format pending vc), R2 keep-code-fix-README, R4 enoent bootstrap-only, R5 0.3.0, R6 one workflow + 1.20/OTP 29 cell, R7 implement pop honestly.
- (2026-08-04) **R3 open**: escript CLI extract vs delete. Blocks WP-05 scope only (AC-05.1, AC-05.3). Audit leans delete.
