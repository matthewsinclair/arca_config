---
verblock: "04 Aug 2026:v0.1: matts - Initial version"
intent_version: 2.18.0
status: WIP
slug: fable-review-of-arca-config-base-code
created: 20260804
completed:
---

# ST0002: Fable review of arca_config base code

## Objective

Audit the arca_config base code with Fable (analysis phase), triage the findings into recurring loss patterns (archetypes), ratify an acceptance contract, and remediate in risk-ordered work packages -- ending with arca_cli rebuilt against the result and its full suite green. Breaking changes are permitted (hv ruling); the current API need not be preserved.

The anchor contract, settled from the findings: **every public return value is a truthful account of what happened on disk, and every documented promise (precedence, notification, location) matches the code.** That is precisely where the library currently lies -- to callers (silent write failures), to subscribers (notification matrix), and to readers (README precedence inverted).

## Context

arca_config is a ~2,800-line JSON file-backed config library (facade + GenServer + ETS cache + polling FileWatcher + legacy Cfg loader) with one live consumer: arca_cli, a git dep on `branch: main`. arca_cli's ST0011 (Fable audit -> breaking 0.5.0, 40/40 ACs) generated the handover that seeded this thread; its session stays live as the verification node (vc) and will run the real acceptance test -- rebuild arca_cli against the new arca_config and re-run its 710 tests.

The analysis phase is complete: 39 findings, 5 archetypes, execution probes confirming the critical claims (silent write success, stale ancestor cache, incoherent notification matrix, nondeterministic domain detection, env-override key collapse). See `design.md` for the ledger and `acceptance.md` for the contract. Constraints that shape remediation:

- **Deletion tripwire**: arca_cli probes `function_exported?(Arca.Config, :register_change_callback, 2)` as a liveness proxy (`arca_cli lib/arca_cli.ex:118-130`). Zero callers is not sufficient grounds to retire a public symbol; the sibling-repo probe (arca_id, arca_dbutils, arca_notionex, arca_doc, arca_optimus: zero references) is on record in design.md.
- arca_cli text-matches our error prose (`lib/arca_cli.ex:1083-1098`); the error-dialect unification must be coordinated with vc.
- Fleet check confirmed drift between arca_cli's pinned `8b30615` and HEAD is mix.lock-only; behaviour is source-identical.

## Related Steel Threads

- ST0001 (COMPLETED) -- Registry integration, FileWatcher, callback system: built the surface this thread audits.
- arca_cli ST0011 (cross-repo) -- the audit pattern this thread follows, and the downstream that verifies it.

## Acceptance

Acceptance Criteria and Acceptance Tests for this steel thread live in `acceptance.md` (the single source of truth). Do not restate ACs here -- see that file for the ratified completeness boundary and live status.

## Related Steel Threads

- [List any related steel threads here]

## Context for LLM

This document represents a single steel thread - a self-contained unit of work focused on implementing a specific piece of functionality. When working with an LLM on this steel thread, start by sharing this document to provide context about what needs to be done.

### How to update this document

1. Update the status as work progresses
2. Update related documents (design.md, impl.md, etc.) as needed
3. Mark the completion date when finished

The LLM should assist with implementation details and help maintain this document as work progresses.
