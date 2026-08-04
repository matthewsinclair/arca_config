---
node: cc
name: Control Claude
role: control
session_id: 797c6bb0-eb52-4b00-9870-3095616dfef2
heartbeat_at: 2026-08-04T19:08Z
status: active
focus: "ST0002 -- 31/38, suite 200 green. WP-01/02/03/04 DONE, WP-05 waiting on the critic pass. Everything else is vc's or hv's"
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

**Read `inbox.vc.md` at every fold, not only at pickup.** Three vc entries (15:59, 16:05, 16:13) sat unread for a whole session because the node did not exist when pickup ran. All three are handled and cleared into `.history/20260804/`; the live inbox is empty.

## DOING

- Resumed post-compact 2026-08-04T18:14Z; still active. Session record for the day is in `.history/20260804/wip.md`; inbox from vc is empty.
- **hv ruled three times on resume**: notification matrix RATIFIED as implemented; AC-00.4 ACCEPTED (contract 38); **R3 = extract** (CLI to `Arca.Config.CLI`, single Optimus dispatch, escript target dropped, `mix arca.config` and `optimus` kept).
- **Landed since**: AT-00.1 consumer contract + AC-02.3 (`afcff58`, `b0b63ab`), WP-02 partial (`f3aad5f`), WP-05 AC-05.1..05.5 (`284a803`), **AC-02.2 the unified dialect (`5978840`) which closes WP-02, gate PASS 5/5**. Contract 20 -> 24 -> 30 -> 31 of 38. Suite 152 -> 200 green (48 doctests, 152 tests), six seeds, compile clean, format clean, no drift.
- **hv delegated R1's wire format to me** ("pick a sensible one"): `{:error, {:config, reason, detail}}`, arca_config first. Decided, shipped, and told to vc with the one-line clause its rebuild needs.
- **critic-elixir is running** for AC-05.6, at hv's instruction. It is the last thing standing between WP-05 and done.

## TODO (what is left, and who it needs)

- **AC-05.6 -- act on the critic-elixir findings.** The only thing left in WP-05 and the only thing left that is mine. Structural half already green.
- **AC-00.1, AC-00.2 -- vc.** No public symbol has been retired, and the removal log now says so with the evidence; both still want vc's ack and the arca_cli rebuild.
- **WP-06** -- release: vc rebuild of arca_cli (710 tests), migration notes, 0.3.0 tag (R5).
- Per-WP cycle unchanged: red-first ATs, implement, green, changed tests flagged in impl.md's ledger, commit.

## Watch-outs

- **Do not delete `register_change_callback/2`.** Zero callers, but `arca_cli.ex:118-130` probes its existence with `function_exported?/2` as a liveness proxy. Delete it and every `save_settings` in arca_cli silently degrades -- no crash, no warning. A call-graph search cannot find this consumer.
- Before retiring **any** public symbol, re-run the fleet probe (AC-00.1). Sibling sweep on 2026-08-04 was clean: `arca_id`, `arca_dbutils`, `arca_notionex`, `arca_doc`, `arca_optimus` have zero `Arca.Config` references.
- arca_cli text-matches our error prose (`arca_cli.ex:1083-1098`). Rewording a not-found message is a silent breaking change to its error dialect until R1 lands on both sides.
- The suite is green and stays green throughout remediation -- it was green across every finding in the ledger. Green is not evidence here; the ATs are.
- **`test/test_helper.exs` fails the run if the suite changes the working tree, the config env vars or `:arca_config`'s application settings.** If a new test needs to mutate any of those, it restores them exactly; the guard names the facet that drifted. Do not silence it by widening the baseline.
- Tests that assert a defect get changed, not preserved, and every such change goes in impl.md's changed-tests ledger for vc.
- **`Cfg.get/1` now reads server state, not the file.** It used to re-read on every call, so setting the env vars was enough to redirect it; it delegates to `Server` now, which holds one loaded configuration. Anything that moves the location must `switch_config_location/1` or `reload/0`. Six seeds missed this; an unseeded run caught it at once.
- `Arca.Config.Cfg` is the **location and load authority** (`config_file/0`, `config_pathname/0`, `config_location/0`, `env_var_prefix/0`, `load/2`), pure over environment and filesystem, used by `Server`, `FileWatcher` and `InitHelper`. The `LegacyCfg` alias is gone (AF-37 resolved in WP-02). It is not legacy and must not be treated as dead.

## Decisions

- (2026-08-04) Claimed ST0002 as cc, confirmed by hv.
- (2026-08-04) Breaking changes permitted; the current API need not be preserved.
- (2026-08-04) SUPERSEDED: "no local vc node". vc provisioned one here at 15:59. Verification still sits with the session that also owns arca_cli, so verifier and real acceptance test remain the same node -- but the channel is now inboxes in this repo, not hv carrying every message.
- (2026-08-04) **AC-05.1 withdrawn and rewritten after ratification.** As ratified it inferred dep removability from in-repo non-reference -- the same inference hv overruled vc for. Default is now KEEP; removal needs positive downstream evidence with the WP-06 rebuild as proof. Ratification covered scope, not an invalid inference inside one AC; catching it was mine to do.
- (2026-08-04) Standing lens adopted from hv's retraction ruling: for anything public in a library -- deps, facade functions, exported helpers -- in-repo silence is evidence of *untested contract surface*, not deadness. Remedy is coverage, not deletion. AC-00.4 proposed on that basis.
- (2026-08-04) Analysis ran on Fable as verification-plus-extension, not cold -- the model switch happened in-session, so the Opus pre-read was in context. Disclosed in design.md rather than papered over; the "independently rediscovered" claim is not made.
- (2026-08-04) hv ratified acceptance.md as the completeness boundary. R1 (shape decided, wire format pending vc), R2 keep-code-fix-README, R4 enoent bootstrap-only, R5 0.3.0, R6 one workflow + 1.20/OTP 29 cell, R7 implement pop honestly.
- (2026-08-04) **R3 DECIDED by hv: extract (option a).** CLI to `Arca.Config.CLI`, single Optimus dispatch, `escript:` target dropped, `mix arca.config` and `optimus` kept. The audit leaned delete, but the mix task -- not the escript -- is the documented path, and extract fixes AF-11 and AF-34 without removing surface a user outside the fleet could be invoking. Executed in `284a803`.
- (2026-08-04) hv **RATIFIED the notification matrix** as implemented, both rules included. AC-03.1 no longer carries the unblessed caveat.
- (2026-08-04) hv **ACCEPTED AC-00.4**. The consumer contract gets pinned by tests here; AT-00.1 is live work and is the direct execution of hv's own standing lens rather than a nice-to-have.
- (2026-08-04) WP-01 kept the mixed error dialect deliberately -- raw posix atoms for write failures, existing strings untouched -- because unifying it is WP-02 under R1 and needs vc. `format_reason/1` makes the bang functions safe for any reason shape without changing today's message text, which arca_cli text-matches.
- (2026-08-04) hv standing rule: test output is dots only. Necessary production logging that a test provokes is captured with `ExUnit.CaptureLog` and asserted, not printed.
- (2026-08-04) **Corrected myself mid-WP-03 on hv's ruling.** I had used "arca_cli registers zero callbacks" as evidence that widening the notification matrix was safe -- the same inference hv overruled, one step removed. An unknown consumer may register one, and the widening makes a callback that writes config reachable on the put path for the first time. Two consequences, both now non-optional: callbacks dispatch off the server process (no deadlock), and a write that changes nothing raises no event (no loop). Both pinned by test.
- (2026-08-04) The no-change-no-event rule is scoped to **writes**, not reloads. Applying it uniformly broke two tests asserting a bare `reload/0` notifies -- the only written record of that contract, so not mine to narrow. `Server.reload_external/0` added for the watcher, which wants write semantics.
- (2026-08-04) **A green suite across six seeds was still hiding a leak.** After WP-04's isolation work the suite passed every seed while the guard still reported `.test_app/` appearing in the repo -- the seeds were green only because the directory already existed at baseline, residue of the previous leak masking the next one. Bisecting per file found two more unrestored global mutations. Lesson for the rest of this thread: seed-sweeps prove order-independence, not isolation. Only the before/after comparison proves isolation.
- (2026-08-04) **AT-05.3 restated rather than implemented as drafted.** It called for a gate asserting declared == referenced deps, which would fail the build for every dependency with no in-repo call site -- hv's overruled inference, encoded as CI, and contradicting AC-05.1 as rewritten. `deps_audit_test.exs` names all thirteen with the reason each is kept and fails on a silent change instead.
- (2026-08-04) **AT-05.1 and part of AC-05.6 are structural tests that read source.** Deliberate: with the backdoor clause gone the old message matches no `handle_info/2` and kills the process, so a behavioural test for "answers no test-only message" would have to assert a crash. Stated in the module rather than left to look like laziness.
- (2026-08-04) **I did not run critic-elixir** for AC-05.6. It needs a subagent and I do not call one unasked. AC-05.6 stays unsatisfied and the gap is on the board rather than papered over.
- (2026-08-04) **Answered R1 empirically instead of waiting.** vc had not moved in two hours with three claimed-dones queued, so I read arca_cli myself: `setting_error/2` already accepts a bare `:not_found` atom and any binary containing "not found", and the proposed 3-tuple matches neither, so it degrades the message without crashing. Sent as a proposal for vc to attack, not as a decision taken. Also corrected my own handover error there: `get_config_location/0` at `cli_command_helper.ex:350` is inside a `@doc` heredoc, so it never raised.
