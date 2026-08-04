---
verblock: "04 Aug 2026:v0.8: matts - ST0002 contract ratified by hv; analysis phase closed, WP-01 next"
---

# Work In Progress

## Current focus: ST0002 -- Fable review of arca_config base code

Analysis phase COMPLETE and contract RATIFIED (2026-08-04). Remediation not yet started; next action is WP-01 (truthful returns).

State of the thread:

- 39-finding ledger in 5 archetypes: `intent/st/ST0002/design.md` (all evidence file:line; 6 findings executed by probe -- scripts + verbatim output in `intent/st/ST0002/probes/`)
- Acceptance contract drafted: `intent/st/ST0002/acceptance.md` -- 36 ACs; `intent ac status ST0002` reads 0/36 BLOCKED (the correct pre-remediation state)
- 6 risk-ordered work packages created (`intent wp list ST0002`), briefs filled, all Not Started
- Anchor contract: every public return value is a truthful account of what happened on disk, and every documented promise (precedence, notification, location) matches the code

Headline findings, all executed not just traced: a `put` against a read-only file logs `:eacces` yet returns `{:ok, "v"}` and serves the phantom value from memory thereafter (AF-01); with no explicit domain, the detection heuristic resolved the config domain to `:elixir_uuid`, an unused dependency (AF-26); a `put` whose target file did not yet exist was silently redirected into the repo root by the location existence-flip (AF-25); the notification matrix is incoherent -- per-key subscribers never fire on external file changes, the watcher's reason to exist (AF-17). Documented, not executed: README states the env-var precedence backwards -- the root cause of arca_cli's A22 (AF-23).

## Rulings (hv, 2026-08-04) -- decisions in design.md

Six decided as proposed: R2 keep-code-and-fix-README, R4 enoent bootstrap-only, R5 semver 0.3.0, R6 one CI workflow + 1.20/OTP 29 cell, R7 implement `Access.pop` honestly. R1 (canonical error shape `{:error, {:config, reason_atom, key_path}}`) decided in shape, wire format pending vc concurrence -- gates WP-02, not WP-01.

**Still open: R3** -- escript CLI, extract-and-fix vs delete. The only outstanding ruling. It scopes WP-05 (AC-05.1, AC-05.3) and nothing earlier; delete would also remove `optimus`, the last non-Jason runtime dep. Audit leans delete.

## Coordination

- Nodes: `hv` = Matthew (adjudication, model switches, release tag); `cc` = this repo's session (author); `vc` = the arca_cli session (verification + the live downstream, 710 tests). Whiteboard at `intent/whiteboard/cc/`; hv carries traffic between repos.
- Deletion tripwire: arca_cli probes `function_exported?(Arca.Config, :register_change_callback, 2)` as a liveness proxy (`arca_cli lib/arca_cli.ex:118-130`). The symbol survives until arca_cli migrates. Sibling fleet (arca_id, arca_dbutils, arca_notionex, arca_doc, arca_optimus) verified clean of Arca.Config references.
- arca_cli pins `8b30615`; drift to HEAD is mix.lock-only (source-identical).

## Next (post-ratification, risk order)

WP-01 truthful returns -> WP-02 one lookup path / one dialect / complete facade -> WP-03 notification + watcher coherence -> WP-04 location model -> WP-05 surface + dependency pruning -> WP-06 vc rebuild of arca_cli + release. Per-WP cycle: red ATs first, implement, green, critic gate, changed-tests flagged in impl.md's ledger, commit.

## Post-ratification corrections (2026-08-04)

vc provisioned a node in this repo at 15:59, after this session's pickup, so three inbox entries went unread until fold time. Acting on them changed the ratified contract in three places, all recorded rather than silently applied:

- **AC-05.1 withdrawn and rewritten.** As ratified it reduced dependencies "to the referenced set" -- inferring removability from in-repo non-reference, which is precisely the inference hv overruled vc for the same day. Default is now KEEP; removal requires positive downstream evidence with the WP-06 arca_cli rebuild as proof. Downstream evidence has since been gathered and is in design.md; it happens to support removal, and still does not license it.
- **AF-40 + AC-04.7 added** from a vc lead, verified here: `config/.env` (present, gitignored) is applied by `System.put_env` during config evaluation and unconditionally overwrites shell-exported config vars. That is the mechanism behind tests writing into the repo root, and the same defect class as arca_cli's A22.
- **AC-00.4 proposed, not ratified** -- hv's inverse scope item from the retraction ruling: pin what downstream relies on with tests here, so the consumer contract is enforced rather than assumed. A genuine scope addition, so it needs an explicit yes. Contract count 36 -> 38 if accepted.

Standing lens adopted from that ruling: for anything public in a library, in-repo silence is evidence of untested contract surface, not deadness.

## Handover to vc

`intent/st/ST0002/handover-to-vc.md` is the self-contained verification package for the arca_cli session: what to read, the provenance disclosure to be sceptical of, five corrections to their original handover note (each with the verifying command), and four asks -- of which Ask 1 (concur on the R1 error shape) gates WP-02.

## Context for LLM

This document is the project-level post-session snapshot; the live channel during a session is `intent/whiteboard/<node>/wip.md`. On restart: run `/in-session`, read this file, then `intent/st/ST0002/design.md` (ledger + rulings) and `acceptance.md` (contract). Do not start remediation while the contract is unratified.
