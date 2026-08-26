---
verblock: "04 Aug 2026:v0.1: matts - Initial version"
wp_id: WP-04
title: "Location model: precedence, domain, isolation"
scope: Small
status: Done
---

# WP-04: Location model: precedence, domain, isolation

## Objective

Kill archetype AR-4 (location is ambient guesswork): ruled precedence documented once and tested end-to-end, deterministic domain, stable resolution, a suite that leaves the world exactly as it found it. Findings AF-23..AF-31 (design.md).

## Deliverables

- Precedence per ruling R2; README rewritten (inverted precedence, false home-dir story, .env scope, one version string)
- config_domain deterministic; started-applications heuristic (probe P1 -> :elixir_uuid) removed
- No file-existence flip in resolution
- Suite isolation: no repo-root/parent/HOME writes, exact env restore, doctests clean up, git status clean after mix test
- async: false justified per module or lifted

## Acceptance

Acceptance Criteria for this work package live in the steel thread's `acceptance.md`, under the `WP-04` heading (single source of truth). Do not restate ACs here.

## Dependencies

- Ruling R2. Independent of WP-02/03 except shared files; sequence after WP-03 to avoid churn.
