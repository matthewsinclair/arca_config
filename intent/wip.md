---
verblock: "04 Aug 2026:v1.0: matts - ST0002 at 30/38; all seven rulings decided; only AC-02.2, AC-05.6 and WP-06 left"
---

# Work In Progress

## Current focus: ST0002 -- Fable review of arca_config base code

Analysis complete, contract ratified, **all seven rulings decided**, and five of six work packages landed or nearly landed. What remains needs someone other than the builder.

| WP    | Archetype                                  | State                                                                  | Gate |
| ----- | -------------------------------------------- | ------------------------------------------------------------------------ | ---- |
| WP-01 | AR-1 success without effect                | DONE `e82dfbc`                                                         | 6/6  |
| WP-02 | AR-2 two of everything                     | AC-02.1/.3/.4/.5 done `b0b63ab` `f3aad5f`; **AC-02.2 needs the R1 wire format** | 4/5  |
| WP-03 | AR-3 notification describes another system | DONE `c66bd29`; matrix ratified by hv                                  | 6/6  |
| WP-04 | AR-4 location is ambient guesswork         | DONE `8d82cf4`                                                         | 7/7  |
| WP-05 | AR-5 shipped scaffolding                   | AC-05.1..05.5 done `284a803`; **AC-05.6 needs the critic-elixir pass**  | 5/6  |
| WP-06 | release                                    | vc rebuild of arca_cli + 0.3.0 tag (R5)                                | --   |

`intent ac status ST0002` reads **30/38 satisfied -- BLOCKED**, which is the correct state.

Suite: **188 passed (48 doctests, 140 tests)**, from a 128 baseline. Deterministic across five seeds, `mix compile --force --warnings-as-errors` clean, `mix format --check-formatted` clean, output is dots only, and a run provably leaves the working tree, the config environment variables and `:arca_config`'s application settings exactly as it found them.

## What changed, in one line each

- **WP-01** -- every write-shaped operation now returns a truthful account of what happened on disk. A `put` against an unwritable file used to log `:eacces`, return `{:ok, value}`, and serve the phantom from memory for the rest of the session.
- **AC-00.4** -- the consumer contract is pinned by tests *here*: every call arca_cli makes, each assertion citing the arca_cli `file:line` that makes it. The `register_change_callback/2` liveness proxy is now a test, so deleting it fails our suite instead of silently stopping every `save_settings` downstream.
- **WP-02** (partial) -- one nested implementation. `Cfg.get/put` delegate to `Server` instead of reading and writing the file behind its back. `Access.pop` actually deletes. The dead `{:ok, conf}` clause is gone, and so is the test that mocked `GenServer` itself to reach it.
- **WP-03** -- one notification matrix, ratified: three channels, five mutation paths, each firing exactly once. The watcher survives a hand-broken config file instead of restarting into permanent silent dormancy.
- **WP-04** -- one resolved config location, no existence flip, no domain guessing, and a README whose precedence table matches the resolver. That inversion was the root cause of arca_cli's A22.
- **WP-05** (partial) -- the CLI is its own module with a single dispatch through its Optimus spec, which was previously unreachable. Both test backdoors are out of production code. One CI workflow. Committed `.arca_config/` artifacts and debug scripts removed.

## Rulings -- all seven decided

R1 shape decided (wire format is the one open coordination item, with vc), R2 keep-code-fix-README, **R3 extract the CLI** (2026-08-04: `Arca.Config.CLI`, single Optimus dispatch, escript target dropped, `mix arca.config` and `optimus` kept), R4 enoent bootstrap-only, R5 semver 0.3.0, R6 one CI workflow + 1.20/OTP 29 cell, R7 implement `Access.pop` honestly.

## What is left

- **AC-02.2** -- the unified error dialect. Needs the R1 wire format. The proposal is with vc: arca_cli's `setting_error/2` already accepts a bare `:not_found` and any binary containing "not found", and the proposed `{:error, {:config, :not_found, key_path}}` matches neither, so it degrades the message rather than crashing. The migration-order choice is hv's.
- **AC-05.6** -- the critic-elixir pass on changed files. The structural half is green; the pass itself needs a subagent, which is hv's to authorise.
- **AC-00.1, AC-00.2** -- vc's ack and the arca_cli rebuild.
- **WP-06** -- migration notes and the 0.3.0 release.

## Coordination

- Nodes: `hv` = Matthew (adjudication, release); `cc` = this repo's builder; `vc` = the validator, one session covering both arca_config and arca_cli. Boards under `intent/whiteboard/`.
- vc's board has read "standby" since 17:20Z with five claimed-dones queued. If it stays dark, AC-00.2 and the R1 concurrence are the two things that genuinely cannot be done from here.
- Deletion tripwire: arca_cli probes `function_exported?(Arca.Config, :register_change_callback, 2)` as a liveness proxy. It is now pinned by a test.

## Breaking changes for the WP-06 migration notes

- Write-shaped operations can fail where they previously could not; `switch_config_location/1` to a location with no config file errors; a `get` before any successful load reports the load error rather than "Key not found".
- A consumer that never set `:config_domain` and relied on auto-detection now gets `:arca_config`. `config_file/0` no longer falls back to the local path when the configured file is absent.
- **`Cfg.get/1` reads server state rather than the file.** Moving the location behind the server's back and expecting reads to follow no longer works -- use `switch_config_location/1` or `reload/0`.
- The `escript` build target is gone; `mix arca.config` replaces it.

## Standing lessons from this thread

- For anything public in a library, in-repo silence is evidence of *untested contract surface*, not deadness. The remedy is coverage, not deletion. hv ruled this after vc's dependency finding; it has since caught four more instances, two of them mine, and it is why nothing public has been retired in the entire thread.
- A test that is the only written record of a contract is not mine to rewrite so my implementation fits.
- **A green suite across many seeds proves order-independence, not isolation, and not even order-independence reliably.** Twice now a multi-seed sweep certified something that a single different ordering broke within minutes.

## Context for LLM

This document is the project-level snapshot; the live channel during a session is `intent/whiteboard/<node>/wip.md`. On restart: run `/in-session`, read this file, then `intent/st/ST0002/impl.md` (as-built + changed-tests ledger + public-symbol removal log), `acceptance.md` (contract + AT status) and `design.md` (ledger + rulings + the ratified notification matrix).
