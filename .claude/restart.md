# Restart -- arca_config

## WIP focus

**ST0002 remediation is complete; arca_config `v0.3.0` is published, tagged and CI-green.** WP-01 through WP-05 are all DONE. Contract is 35/38 -- BLOCKED, and correctly so: the three open ACs are all vc's.

**Nothing is buildable here right now.** Waiting on vc: rebuild arca_cli, report, ack the removal log. Held for the day at hv's instruction.

## Next

- If vc reports failures from the arca_cli rebuild, they come back here as fixes. That is the one path that reopens work.
- Exactly one arca_cli test fails by design (`error_format_test.exs`, "failure: a setting that does not exist"). The one-line fix belongs in arca_cli and is in `CHANGELOG.md`.

## Start here

1. `/in-session` (loads skills, releases the prompt gate, picks up the whiteboard)
2. `intent/wip.md` -- project snapshot
3. `intent/restart.md` -- fuller restart context, including the traps below
4. `intent/st/ST0002/release-verification.md` -- the handover package for vc

## Traps

- Never delete `Arca.Config.register_change_callback/2` -- arca_cli probes it with `function_exported?/2` as a liveness check. Pinned by `consumer_contract_test.exs`.
- In a library, public + no in-repo callers = **untested contract surface**, not dead code.
- `mix compile --warnings-as-errors` cannot see test files; use `mix test --warnings-as-errors`.
- `test_helper.exs` fails the run on any working-tree, config-env or app-env drift. Do not widen the baseline.
- Suite output is dots only (`ExUnit.start(capture_log: true)`). Assert on logs with `capture_log/1`.
- Coverage threshold 90, enforced, currently 90.47%.
