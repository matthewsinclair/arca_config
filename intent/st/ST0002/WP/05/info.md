---
verblock: "04 Aug 2026:v0.1: matts - Initial version"
wp_id: WP-05
title: "Surface and dependency pruning"
scope: Small
status: WIP
---

# WP-05: Surface and dependency pruning

## Objective

Kill archetype AR-5 (shipped scaffolding): the product surface carries only the product. Findings AF-32..AF-36, AF-38, AF-39 plus AF-11/12/14/15 residue (design.md).

## Deliverables

- Deps cut to referenced set (fleet-probe evidence per removal, AC-00.1); dotenv/certifi/castore/owl/table_rex/ucwidth/pathex/elixir_uuid/ok resolved per ruling R3
- CLI ruling R3 executed: single dispatch or escript removed; facade thinned to delegation (CLI/watch_loop/convert extracted)
- Test backdoors out of Server/FileWatcher; dead support code removed
- One CI workflow per ruling R6; cruft (AGENTS.md.bak, .backup/, committed .arca_config artifacts, debug scripts) resolved
- critic-elixir clean at >= warning on changed files

## Acceptance

Acceptance Criteria for this work package live in the steel thread's `acceptance.md`, under the `WP-05` heading (single source of truth). Do not restate ACs here.

## Dependencies

- Rulings R3, R6. After WP-02 (facade shape settles first).
