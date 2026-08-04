---
node: cc
name: Control Claude
role: control
session_id: 797c6bb0-eb52-4b00-9870-3095616dfef2
heartbeat_at: 2026-08-04T18:20Z
status: active
focus: "ST0002 -- WP-01 + WP-03 + WP-04 DONE (19/38, suite 152 green); WP-05 needs R3, WP-02 held for vc on R1"
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

- **WP-01 (AR-1), WP-03 (AR-3) and WP-04 (AR-4) all DONE** (2026-08-04). Gates PASS 6/6, 6/6, 7/7; contract 19/38. Suite 152 green (was 128) across 7 seeds, `--warnings-as-errors` clean, dots-only output. As-built + changed-tests ledger in `intent/st/ST0002/impl.md`.
- **The suite now proves its own isolation.** `test_helper.exs` baselines the working tree, config env vars, `:arca_config` app settings and known escape paths, and fails the run on drift. It caught a leak that six green seeds had missed, because the residue of the previous run was hiding it.
- **Ready for vc**: three claimed-dones. Fifteen changed/rewritten tests in the ledger.
- **Needs hv**: the notification matrix (design.md, AC-03.1 says "ratified" -- implemented and pinned, not blessed), AC-00.4, and **ruling R3, which now blocks the only remaining buildable WP**.
- Awaiting vc on the R1 error shape (gates WP-02).
- Inbox check at pickup 16:54Z: no new vc entries since the three read at fold (15:59, 16:05, 16:13). vc active, heartbeat 16:35Z, focus "standby -- verify ST0002 at plan-ratification and at each claimed-done".

## TODO (risk order)

- **Both remaining WPs are now blocked on someone else.** WP-02 needs vc's answer on the R1 error shape; WP-05 needs hv's ruling R3 (escript: extract vs delete). Nothing else in the thread is buildable without one of those two.
- WP-05 has a part that does not need R3 -- test backdoors out of production modules (AC-05.2), cruft removal (AC-05.5), CI consolidation (AC-05.4, ruling R6) -- so that is the fallback if R3 stays open.
- WP-06 vc rebuild of arca_cli (710 tests) + release.
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
- (2026-08-04) **Corrected myself mid-WP-03 on hv's ruling.** I had used "arca_cli registers zero callbacks" as evidence that widening the notification matrix was safe -- the same inference hv overruled, one step removed. An unknown consumer may register one, and the widening makes a callback that writes config reachable on the put path for the first time. Two consequences, both now non-optional: callbacks dispatch off the server process (no deadlock), and a write that changes nothing raises no event (no loop). Both pinned by test.
- (2026-08-04) The no-change-no-event rule is scoped to **writes**, not reloads. Applying it uniformly broke two tests asserting a bare `reload/0` notifies -- the only written record of that contract, so not mine to narrow. `Server.reload_external/0` added for the watcher, which wants write semantics.
- (2026-08-04) **A green suite across six seeds was still hiding a leak.** After WP-04's isolation work the suite passed every seed while the guard still reported `.test_app/` appearing in the repo -- the seeds were green only because the directory already existed at baseline, residue of the previous leak masking the next one. Bisecting per file found two more unrestored global mutations. Lesson for the rest of this thread: seed-sweeps prove order-independence, not isolation. Only the before/after comparison proves isolation.
- (2026-08-04) Ruling R4 turned out to be a test-hygiene detector: while a load from a nonexistent location reported success with an empty config, a test could destroy the location it depended on and still pass. Two such tests surfaced the moment enoent stopped being success. Expect more in WP-04 (AC-04.5).
