---
verblock: "04 Aug 2026:v0.1: matts - Initial version"
wp_id: WP-06
title: "Downstream verification and release"
scope: Small
status: Not Started
---

# WP-06: Downstream verification and release

## Objective

Prove the release against the one real consumer: vc rebuilds arca_cli on the final arca_config and its full suite passes; ship with migration notes, CHANGELOG, version, tag. ST-level ACs AC-00.1..3 close here.

## Deliverables

- vc report: arca_cli mix.lock advanced from 8b30615, suite green (or failures triaged back into WPs)
- Migration notes covering every breaking change + the three now-removable arca_cli defensive strata
- usage-rules.md carries real consumer API guidance
- CHANGELOG, semver per ruling R5, tag held by hv

## Acceptance

Acceptance Criteria for this work package live in the steel thread's `acceptance.md`, under the `WP-06` heading (single source of truth). Do not restate ACs here.

## Dependencies

- All prior WPs; rulings R5; vc execution (hv carries traffic between repos).
