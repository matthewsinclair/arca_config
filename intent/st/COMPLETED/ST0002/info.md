---
verblock: "04 Aug 2026:v1.0: matts - remediation complete, 0.3.0 published; open ACs are vc's and hv's"
intent_version: 2.18.0
status: Completed
slug: fable-review-of-arca-config-base-code
created: 20260804
completed: 2026-08-04T20:07:55Z
---

# ST0002: Fable review of arca_config base code

## Objective

Audit the arca_config base code with Fable (analysis phase), triage the findings into recurring loss patterns (archetypes), ratify an acceptance contract, and remediate in risk-ordered work packages -- ending with arca_cli rebuilt against the result and its full suite green. Breaking changes are permitted (hv ruling); the current API need not be preserved.

The anchor contract, settled from the findings: **every public return value is a truthful account of what happened on disk, and every documented promise (precedence, notification, location) matches the code.** That is precisely where the library currently lies -- to callers (silent write failures), to subscribers (notification matrix), and to readers (README precedence inverted).

## Context

arca_config is a ~2,800-line JSON file-backed config library (facade + GenServer + ETS cache + polling FileWatcher + legacy Cfg loader) with one live consumer: arca_cli, a git dep on `branch: main`. arca_cli's ST0011 (Fable audit -> breaking 0.5.0, 40/40 ACs) generated the handover that seeded this thread; its session stays live as the verification node (vc) and will run the real acceptance test -- rebuild arca_cli against the new arca_config and re-run its 710 tests.

**Status, 2026-08-04**: remediation is complete and 0.3.0 is published at `03969fa` (CI green, 222 tests, coverage 90.47%). WP-01 through WP-05 are DONE. The contract stands at **34/38 -- BLOCKED**, and the four open ACs are the ones this thread was always going to end on: vc's ack of the removal log (AC-00.1), vc's rebuild of arca_cli (AC-00.2), vc's report (AC-06.1), and hv's tag (AC-06.3). See `release-verification.md` for the handover.

The analysis phase found 39 findings, 5 archetypes, execution probes confirming the critical claims (silent write success, stale ancestor cache, incoherent notification matrix, nondeterministic domain detection, env-override key collapse). One more finding (AF-40) came from a vc lead, and a later critic pass added 21 of its own -- four of them criticals the audit missed, including data loss on the write path. See `design.md` for the ledger and `acceptance.md` for the contract. Constraints that shaped remediation:

- **Deletion tripwire**: arca_cli probes `function_exported?(Arca.Config, :register_change_callback, 2)` as a liveness proxy (`arca_cli lib/arca_cli.ex:118-130`). Zero callers is not sufficient grounds to retire a public symbol; the sibling-repo probe (arca_id, arca_dbutils, arca_notionex, arca_doc, arca_optimus: zero references) is on record in design.md.
- arca_cli text-matches our error prose (`lib/arca_cli.ex:1083-1098`); the error-dialect unification must be coordinated with vc.
- Fleet check confirmed drift between arca_cli's pinned `8b30615` and HEAD is mix.lock-only; behaviour is source-identical.

## Related Steel Threads

- ST0001 (COMPLETED) -- Registry integration, FileWatcher, callback system: built the surface this thread audits.
- arca_cli ST0011 (cross-repo) -- the audit pattern this thread follows, and the downstream that verifies it.

## Acceptance

Acceptance Criteria and Acceptance Tests for this steel thread live in `acceptance.md` (the single source of truth). Do not restate ACs here -- see that file for the ratified completeness boundary and live status.

## Context for LLM

This document represents a single steel thread - a self-contained unit of work focused on implementing a specific piece of functionality. When working with an LLM on this steel thread, start by sharing this document to provide context about what needs to be done.

### How to update this document

1. Update the status as work progresses
2. Update related documents (design.md, impl.md, etc.) as needed
3. Mark the completion date when finished

The LLM should assist with implementation details and help maintain this document as work progresses.
