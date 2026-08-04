---
node: cc
name: Control Claude
role: control
session_id: 797c6bb0-eb52-4b00-9870-3095616dfef2
heartbeat_at: 2026-08-04T17:15Z
status: active
focus: "ST0002 -- WP-01 truthful returns DONE (gate 6/6, suite 134 green); WP-03 next, WP-02 held for vc on R1"
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

- **WP-01 truthful returns (AR-1) DONE** (2026-08-04). Gate PASS 6/6; contract 6/38. Suite 134 green (was 128) across 8 seeds, `--warnings-as-errors` clean, dots-only output, `git status` unchanged by a run. As-built + changed-tests ledger in `intent/st/ST0002/impl.md`.
- **Ready for vc**: WP-01 is a claimed-done, which is vc's fire condition. Seven changed/rewritten tests in the ledger, two of them hygiene rather than defect-assertions.
- Awaiting vc on the R1 error shape (gates WP-02) and hv on AC-00.4 + ruling R3 (gates WP-05 scope).
- Inbox check at pickup 16:54Z: no new vc entries since the three read at fold (15:59, 16:05, 16:13). vc active, heartbeat 16:35Z, focus "standby -- verify ST0002 at plan-ratification and at each claimed-done".

## TODO (risk order)

- **WP-03 notification + watcher coherence** -- next action. WP-02 is blocked on vc's answer to the R1 error shape; WP-03 touches none of it.
- WP-02 one lookup path / one dialect / complete facade -- needs vc concurrence on the R1 error shape before it lands.
- WP-04 location model. WP-05 pruning (needs R3). WP-06 vc rebuild of arca_cli (710 tests) + release.
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
- (2026-08-04) WP-01 kept the mixed error dialect deliberately -- raw posix atoms for write failures, existing strings untouched -- because unifying it is WP-02 under R1 and needs vc. `format_reason/1` makes the bang functions safe for any reason shape without changing today's message text, which arca_cli text-matches.
- (2026-08-04) hv standing rule: test output is dots only. Necessary production logging that a test provokes is captured with `ExUnit.CaptureLog` and asserted, not printed.
- (2026-08-04) Ruling R4 turned out to be a test-hygiene detector: while a load from a nonexistent location reported success with an empty config, a test could destroy the location it depended on and still pass. Two such tests surfaced the moment enoent stopped being success. Expect more in WP-04 (AC-04.5).
