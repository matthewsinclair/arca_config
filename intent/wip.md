---
verblock: "04 Aug 2026:v0.9: matts - ST0002 WP-01/03/04 landed; both remaining WPs blocked on rulings"
---

# Work In Progress

## Current focus: ST0002 -- Fable review of arca_config base code

Analysis phase complete, contract ratified, and **three of five remediation work packages landed**. Both remaining ones are blocked on an answer rather than on effort.

| WP    | Archetype                          | State                          | Gate |
| ----- | ------------------------------------ | -------------------------------- | ---- |
| WP-01 | AR-1 success without effect         | DONE `e82dfbc`                 | 6/6  |
| WP-02 | AR-2 two of everything              | BLOCKED -- vc must concur on the R1 error shape | --   |
| WP-03 | AR-3 notification describes another system | DONE `c66bd29`          | 6/6  |
| WP-04 | AR-4 location is ambient guesswork  | DONE `8d82cf4`                 | 7/7  |
| WP-05 | AR-5 shipped scaffolding            | BLOCKED -- hv must rule R3 (escript: extract vs delete) | --   |
| WP-06 | release                             | vc rebuild of arca_cli + tag   | --   |

`intent ac status ST0002` reads **19/38 satisfied -- BLOCKED**, which is the correct state: 19 covered by green acceptance tests or named evidence, 19 still ahead.

Suite: **152 passed (41 doctests, 111 tests)**, from a 128 baseline. Deterministic across seven seeds, `mix compile --force --warnings-as-errors` clean, output is dots only, and a test run provably leaves the working tree, the config environment variables and `:arca_config`'s application settings exactly as it found them.

## What changed, in one line each

- **WP-01** -- every write-shaped operation now returns a truthful account of what happened on disk. A `put` against an unwritable file used to log `:eacces` and return `{:ok, value}`, then serve the phantom from memory for the rest of the session.
- **WP-03** -- one notification matrix: three channels, five mutation paths, each firing exactly once. The watcher survives a hand-broken config file instead of restarting into permanent silent dormancy, and the write-suppression window that swallowed external edits is gone rather than patched.
- **WP-04** -- one resolved config location, no existence flip, no domain guessing, and a README whose precedence table matches the resolver. That inversion was the root cause of arca_cli's A22.

## Rulings

Decided (hv, 2026-08-04): R1 shape (wire format pending vc), R2 keep-code-fix-README, R4 enoent bootstrap-only, R5 semver 0.3.0, R6 one CI workflow + 1.20/OTP 29 cell, R7 implement `Access.pop` honestly.

**Open, and now on the critical path:**

- **R3** -- escript CLI, extract-and-fix vs delete. Scopes WP-05 (AC-05.1, AC-05.3). Delete would also remove `optimus`, the last non-Jason runtime dep. Audit leans delete.
- **The notification matrix** in `design.md` -- AC-03.1 asks for a *ratified* matrix; the one implemented is pinned by test but not blessed.
- **AC-00.4** -- proposed scope addition: pin downstream-relied-upon surface with tests here.

## Coordination

- Nodes: `hv` = Matthew (adjudication, release); `cc` = this repo's builder; `vc` = the validator, one session covering both arca_config and arca_cli. Boards under `intent/whiteboard/`.
- Three claimed-dones are waiting on vc, whose board still reads standby.
- Deletion tripwire: arca_cli probes `function_exported?(Arca.Config, :register_change_callback, 2)` as a liveness proxy. The symbol survives until arca_cli migrates.

## Standing lessons from this thread

- For anything public in a library, in-repo silence is evidence of *untested contract surface*, not deadness. The remedy is coverage, not deletion. hv ruled this after vc's dependency finding; it has since caught two more instances, one of them mine.
- A test that is the only written record of a contract is not mine to rewrite so my implementation fits. Twice a rule had to be narrowed instead.
- A green suite across many seeds proves order-independence, not isolation. Six consecutive green seeds hid a working-tree leak, because the previous run's residue masked it. Only a before/after comparison found it.

## Context for LLM

This document is the project-level snapshot; the live channel during a session is `intent/whiteboard/<node>/wip.md`. On restart: run `/in-session`, read this file, then `intent/st/ST0002/impl.md` (as-built + changed-tests ledger), `acceptance.md` (contract + AT status) and `design.md` (ledger + rulings + notification matrix).
