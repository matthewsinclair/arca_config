---
verblock: "04 Aug 2026:v0.1: matts - Initial version"
wp_id: WP-02
title: "One lookup path, one dialect, complete facade"
scope: Small
status: WIP
---

# WP-02: One lookup path, one dialect, complete facade

## Objective

Kill archetype AR-2 (two of everything): one nested get/put/delete/write implementation, one canonical error dialect (ruling R1, coordinated with vc), a complete facade. Findings AF-08..AF-13, AF-16, AF-37 (design.md).

## Deliverables

- Cfg/Server duplication collapsed to one write path; every write registers exactly one watcher token
- Canonical missing-key error shape across facade/Server/Cfg-successor/Map; four dialects gone
- Facade gains delete/1, delete!/1, get_config_location/0 (arca_cli's phantom call becomes real)
- Access.pop honest per ruling R7; dead {:ok, conf} clause + GenServer-meck test gone
- LegacyCfg ownership resolved per AF-37

## Acceptance

Acceptance Criteria for this work package live in the steel thread's `acceptance.md`, under the `WP-02` heading (single source of truth). Do not restate ACs here.

## Dependencies

- WP-01 (truthful returns underneath the unified path); rulings R1, R7; vc agreement on the error shape (arca_cli parses it).
