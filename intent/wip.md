---
verblock: "04 Aug 2026:v2.0: matts - ST0002 remediation complete, 0.3.0 published; awaiting vc's rebuild and hv's tag"
---

# Work In Progress

## Current focus: ST0002 -- Fable review of arca_config base code

**Remediation is complete and 0.3.0 is published.** Five of six work packages are done; the sixth is downstream verification and release, and none of it can be done from this repository.

| WP    | Archetype                                  | State                                  | Gate |
| ----- | -------------------------------------------- | ---------------------------------------- | ---- |
| WP-01 | AR-1 success without effect                | DONE `e82dfbc`                         | 6/6  |
| WP-02 | AR-2 two of everything                     | DONE `f3aad5f` `5978840`               | 5/5  |
| WP-03 | AR-3 notification describes another system | DONE `c66bd29`                         | 6/6  |
| WP-04 | AR-4 location is ambient guesswork         | DONE `8d82cf4`                         | 7/7  |
| WP-05 | AR-5 shipped scaffolding                   | DONE `284a803` `27620e9`               | 6/6  |
| WP-06 | release                                    | vc's rebuild + hv's tag                | --   |

`intent ac status ST0002` reads **34/38 satisfied -- BLOCKED**, which is correct: the four open ACs are vc's ack, vc's rebuild, vc's report, and hv's tag.

| | |
| --- | --- |
| Published | `03969fa` on `main`, GitHub `matthewsinclair/arca_config`. Version 0.3.0 (R5), **untagged** |
| Suite | 222 passed (48 doctests, 174 tests), from a 128 baseline. 8 seeds, zero stray output |
| Gates | compile and test both `--warnings-as-errors` clean, format clean, coverage 90.47% against an enforced threshold of 90 |
| CI | green on 1.18.0/OTP 27, 1.18.4/OTP 28, 1.20.2/OTP 29 |
| Isolation | a run provably leaves the working tree, the config env vars and `:arca_config`'s app settings exactly as it found them |

## What changed, in one line each

- **WP-01** -- every write-shaped operation returns a truthful account of what happened on disk. A `put` against an unwritable file used to log `:eacces`, return `{:ok, value}`, and serve the phantom from memory for the rest of the session.
- **WP-02** -- one nested implementation and one error dialect. `Cfg.get/put` delegate to `Server` instead of reading and writing the file behind its back; every failure is `{:error, {:config, reason, detail}}`; `Access.pop` actually deletes.
- **WP-03** -- one ratified notification matrix: three channels, five mutation paths, each firing exactly once. The watcher survives a hand-broken config file instead of restarting into permanent silent dormancy.
- **WP-04** -- one resolved config location: no existence flip, no domain guessing, and a README whose precedence table matches the resolver. That inversion was the root cause of arca_cli's A22.
- **WP-05** -- the CLI is its own module with a single dispatch through its Optimus spec, which was previously unreachable. Test backdoors out of production code, one CI workflow, committed artifacts removed.
- **AC-00.4** -- the consumer contract is pinned by tests *here*: every call arca_cli makes, each citing the arca_cli `file:line`.
- **AC-05.6** -- a critic pass found 21 further findings, all closed, including four criticals the audit missed.

## What is left

- **AC-00.2** -- vc rebuilds arca_cli against `03969fa` and runs its full suite. **One test will fail by design**; the one-line fix is in `CHANGELOG.md` and in the handover.
- **AC-00.1** -- vc's ack on the public-symbol removal log. No public symbol was retired in the entire thread.
- **AC-06.1** -- vc's report on that rebuild.
- **AC-06.3** -- hv tags `v0.3.0`. This repo has no tags at all yet.

Handover package: `intent/st/ST0002/release-verification.md` -- self-contained, written for the validation node.

## Rulings -- all seven decided and executed

R1 shape by hv with the wire format delegated to the builder (`{:error, {:config, reason, detail}}`, arca_config first); R2 keep-code-fix-README; R3 **extract** the CLI; R4 enoent bootstrap-only; R5 semver 0.3.0; R6 one CI workflow with a 1.20/OTP 29 cell; R7 implement `Access.pop` honestly. hv also ratified the notification matrix and accepted AC-00.4 as a scope addition.

## Breaking changes for consumers

Full detail in `CHANGELOG.md`. In risk order for arca_cli: `Cfg.get/1` reads server state rather than the file; writes can fail; `delete/1` on an absent key errors; a `put` against an unparseable file is refused rather than repairing it; `switch_config_location/1` to a location with no file errors; the config domain is never guessed; `config_file/0` no longer falls back; domain-specific env vars outrank generic ones; the escript target is gone in favour of `mix arca.config`.

## Standing lessons from this thread

- For anything public in a library, in-repo silence is evidence of **untested contract surface**, not deadness. The remedy is coverage, not deletion. This caught five instances, three of them mine, and is why nothing public was retired.
- **A thorough audit still had holes.** The critic pass found four criticals the 40-finding Fable audit missed, one of which was data loss on the write path -- the very archetype the thread was built around.
- **A green suite proves less than it looks.** Seed sweeps prove order-independence, not isolation, and twice a multi-seed sweep certified something one different ordering broke minutes later. Separately, a mock returning the old shape kept a test green through the exact contract change it existed to cover.
- **Gates only cover what they can see.** `mix compile --warnings-as-errors` never sees test files, and a coverage threshold behind `|| true` can never fail. Both were true here for the life of the project.
- A test that is the only written record of a contract is not the implementer's to rewrite so their change fits. That happened twice; both times the implementation was narrowed instead.

## Context for LLM

This document is the project-level snapshot; the live channel during a session is `intent/whiteboard/<node>/wip.md`. On restart: run `/in-session`, read this file, then `intent/st/ST0002/release-verification.md` (what is outstanding and for whom), `impl.md` (as-built, changed-tests ledger, removal log), `acceptance.md` (contract + live AT status), `design.md` (findings ledger, archetypes, rulings, the ratified matrix).
