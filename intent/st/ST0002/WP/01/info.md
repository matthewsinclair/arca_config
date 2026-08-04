---
verblock: "04 Aug 2026:v0.1: matts - Initial version"
wp_id: WP-01
title: "Truthful returns: persistence failures surface"
scope: Small
status: Not Started
---

# WP-01: Truthful returns: persistence failures surface

## Objective

Kill archetype AR-1 (success without effect): every write-shaped operation returns a truthful account of what happened on disk, and in-memory state never advances past a failed persist. Findings AF-01..AF-07 (design.md).

## Deliverables

- `Server.put/2`, `delete/1` propagate write failures; state/cache untouched on failure (probe P3 scenario turns red-first, then green)
- `put!/delete!` raise on persistence failure; load failures surface as load errors, not key-misses
- Cache fabricate-success rescues removed; honest cache-unavailable failure
- `load_config_phase/0` aggregates override failures; enoent semantics per ruling R4
- Changed tests flagged in impl.md ledger (switch_location_test nonexistent-path test is known-in-advance)

## Acceptance

Acceptance Criteria for this work package live in the steel thread's `acceptance.md`, under the `WP-01` heading (single source of truth). Do not restate ACs here.

## Dependencies

- Contract ratification (hv) + ruling R4. First WP to land: later WPs' error paths build on truthful returns.
