# Implementation - ST0002: Fable review of arca_config base code

## Implementation

Remediation not started; holding for hv ratification of acceptance.md + rulings R1-R7 (design.md).

Baseline (2026-08-04, HEAD 9925115): `mix compile --force --warnings-as-errors` clean; `mix test` 128 passed (41 doctests, 87 tests). lib/ 2,771 LOC over 9 files; test/ 2,112 LOC over 9 files + support.

Probe artifacts: `probes/` (scripts + verbatim output), durable in this ST directory; results transcribed into design.md's ledger (probes P1/P2/P3/P3b/P5/P7).

## Changed-tests ledger

Every test changed because it asserted a defect gets a row here (AC-00.3). Flag each to vc.

| Test                                    | Asserted defect                                 | Change | WP  |
| --------------------------------------- | ----------------------------------------------- | ------ | --- |
| (none yet -- remediation not started)   |                                                 |        |     |

Known-in-advance candidates: switch_location_test.exs:217-231, map_test.exs:174-180, server_test.exs:341-375, file_watcher_test.exs:73-104, cfg_test.exs:99-109, auto_config_test.exs theatre tests.

## Public-symbol removal log

Per AC-00.1: each retired public symbol gets a row with the fleet-probe evidence re-run at removal time.

| Symbol                                | Probe result | vc ack |
| ------------------------------------- | ------------ | ------ |
| (none yet)                            |              |        |

## Technical Details

- Commit discipline: per-WP batches behind compile + test gates; no `--no-verify`.
- The `register_change_callback/2` tripwire (arca_cli liveness proxy) must survive every WP until arca_cli migrates. See info.md context.

## Challenges & Solutions

(To be filled as remediation proceeds.)
