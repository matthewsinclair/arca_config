---
verblock: "04 Aug 2026:v0.1: matts - Initial version"
wp_id: WP-03
title: "Notification and watcher coherence"
scope: Small
status: Not Started
---

# WP-03: Notification and watcher coherence

## Objective

Kill archetype AR-3 (notifications describe a different system): one ratified notification matrix, a watcher that survives reality, a cache that tells the truth after writes. Findings AF-17..AF-22 (design.md).

## Deliverables

- Ratified matrix implemented + documented on subscribe/register_change_callback/add_callback; per-key fires on external/reload/switch; 0-arity double-fire gone
- Watcher survives malformed JSON (log, keep last-good, keep watching) and recovers on next valid write
- Post-write suppression window no longer swallows external edits (token identity or re-check)
- Ancestor cache coherent after nested put (probe P2 scenario red-first)
- file_watcher_test suppress-everything test rewritten (changed-tests ledger)

## Acceptance

Acceptance Criteria for this work package live in the steel thread's `acceptance.md`, under the `WP-03` heading (single source of truth). Do not restate ACs here.

## Dependencies

- WP-01, WP-02 (matrix rides the unified write path).
