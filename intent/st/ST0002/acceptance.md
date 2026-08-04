---
verblock: "04 Aug 2026:v0.3: matts - ST0002 contract RATIFIED by hv; rulings R1/R2/R4/R5/R6/R7 decided, R3 open"
st_id: ST0002
title: "Fable review of arca_config base code -- acceptance contract"
---

# ST0002 Fable review of arca_config base code -- Acceptance

> Canonical acceptance contract for ST0002. Acceptance Criteria (AC) are the ratified completeness boundary; Acceptance Tests (AT) are the small red-to-green tests that prove them. Real test code lives in the suite (paths cited below); this file is the contract plus the AC-to-AT coverage map plus live status. info.md / WP info.md reference this file and never restate ACs (one home).
>
> Done = every AC is covered by a GREEN AT, or (for a non-test AC) its named evidence is satisfied, AND the AC set is the ratified full boundary. Done is read from this map, never from a hand-ticked box.
>
> Change control: clarifying an AC or AT is verifier-and-builder; shrinking scope, or weakening an AT to make it pass, needs the owner.
>
> AT status vocabulary: to-write (red-first) | red | green | n/a (non-test: doc / eyeball / gate).
>
> Non-test ACs carry their state inline -- `-- evidence: <ref> -- satisfied: yes|no` on the AC line; test-backed ACs are satisfied by a green covering AT (computed, never written). Multi-AC coverage on an AT is comma-separated.
>
> **STATUS: RATIFIED by hv, 2026-08-04.** This is the completeness boundary for ST0002. Scope changes and AT weakenings now need hv; clarifications are verifier-and-builder.
>
> Ruling state (design.md carries the decisions): R2, R4, R5, R6, R7 decided as proposed. R1 decided in shape, final wire format pending vc concurrence (arca_cli parses it) -- does not block WP-01. **R3 (escript CLI: extract vs delete) remains OPEN** and is the only ruling still needed; it scopes WP-05 (AC-05.3) and nothing earlier.
>
> **Post-ratification amendments, 2026-08-04** (recorded rather than silently applied): AC-05.1 was rewritten after hv's ruling on vc's dependency retraction -- as ratified it inferred removability from in-repo non-reference, which is the inference hv overruled. It now defaults to KEEP and requires downstream evidence. AC-04.7 added (config/.env overriding shell env during config evaluation -- AF-40, from a vc lead, verified here). AC-00.4 is **proposed, not ratified**: it is the inverse scope item hv named, and it is a genuine scope addition, so it needs an explicit yes. Count moves 36 -> 38 if AC-00.4 is accepted.

## Acceptance Criteria

### ST-level

- AC-00.1 (non-test) No public symbol is retired without the sibling-fleet probe (`function_exported?` / `Code.ensure_loaded?` / direct refs) re-run at removal time and recorded -- the `register_change_callback/2` tripwire (arca_cli liveness proxy) survives or arca_cli is migrated first -- evidence: impl.md removal log + vc ack -- satisfied: no
- AC-00.2 (non-test) arca_cli rebuilt against the final arca_config (mix.lock advanced from 8b30615) and its full suite passes, executed by vc -- evidence: vc report -- satisfied: no
- AC-00.3 (non-test) Every test changed because it asserted a defect is listed in impl.md's changed-tests ledger with before/after behaviour -- evidence: impl.md ledger -- satisfied: no
- AC-00.4 (PROPOSED -- scope addition, needs hv) What downstream relies on arca_config for is identified and pinned by tests **here**, so the consumer contract is enforced rather than assumed. Arises from hv's ruling on the dependency retraction: in-repo silence over public surface signals untested contract surface, and the remedy is coverage, not deletion. Covered by AT-00.1

### WP-01 -- Truthful returns (status: TODO)

- AC-01.1 `put/2` and `delete/1` return `{:error, _}` when persistence fails, and neither server state nor cache advances past the failed write (a subsequent `get` reflects disk, not the phantom value)
- AC-01.2 `put!/2` and `delete!/1` raise on persistence failure
- AC-01.3 A failed initial/on-demand config load surfaces as a load error to the caller, not as "key not found" for every key thereafter
- AC-01.4 Cache API clauses that fabricate success when the cache is unavailable are removed; cache unavailability is an honest failure distinct from key-miss
- AC-01.5 A failed env-override application is surfaced (aggregate result from `load_config_phase/0`), not silently dropped
- AC-01.6 (ruling R4) `switch_config_location/1` to a nonexistent path returns an error and leaves the previous location live; enoent-as-empty-config survives only for the documented first-run bootstrap path

### WP-02 -- One lookup path, one dialect, complete facade (status: TODO)

- AC-02.1 Exactly one nested get/put/delete/write implementation remains; every public write path registers the watcher write-token exactly once (no self-notification fork)
- AC-02.2 (ruling R1) A missing key yields one canonical machine-matchable error shape from every entry point (facade, Server, Cfg-or-successor, Map); the four current dialects are gone
- AC-02.3 The facade exposes `delete/1`, `delete!/1`, and a location-inspection API (`get_config_location/0` returning path, file, and source) such that arca_cli's `cli_command_helper.ex:350` call works unmodified
- AC-02.4 (ruling R7) `Access.pop/2` and `get_and_update/3`'s `:pop` actually delete through the one write path, or the Access implementation is removed
- AC-02.5 The dead `{:ok, conf}` clause in `notify_external_change/0` is gone, `:get_config` has a single reply shape, and no test mocks GenServer to reach dead code

### WP-03 -- Notification and watcher coherence (status: TODO)

- AC-03.1 A ratified notification matrix (channels x mutation paths) is implemented: each channel fires exactly once per mutation event on every path it covers, and the covered set is documented on `subscribe/1`, `register_change_callback/2`, and `add_callback/1`
- AC-03.2 Per-key subscribers are notified on external file changes (the watcher's reason to exist) and on reload/switch, per the ratified matrix
- AC-03.3 0-arity callbacks fire exactly once per externally-detected change (double-fire eliminated)
- AC-03.4 The watcher survives malformed JSON: parse failure logs, retains last-good state, keeps watching (no crash-to-dormancy); recovery detects the next valid write
- AC-03.5 An external edit landing inside the post-write suppression window is not lost (token identity compared, or equivalent re-check)
- AC-03.6 After `put/2` returns, a `get/1` of any ancestor of the written path reflects the write (cache coherence)

### WP-04 -- Location model (status: TODO)

- AC-04.1 (ruling R2) Precedence is ruled, implemented, and documented identically in README and moduledoc, with a single test asserting the full chain end-to-end
- AC-04.2 `config_domain/0` is deterministic: explicit configuration or a documented stable default; the started-applications heuristic (probe P1: `:elixir_uuid`) is removed
- AC-04.3 Location resolution is stable within a session: no file-existence flip between reads and writes
- AC-04.4 (non-test) README matches behaviour: precedence order, actual default paths (CWD-relative or ruled otherwise), `.env` section corrected to project-local scope, one version string -- evidence: README diff reviewed against AC-04.1 test -- satisfied: no
- AC-04.5 After `mix test`, the repo tree is clean: no writes to the repo root, its parent, or HOME; `git status --porcelain` empty; env mutations restored exactly (superset-restore fixed; doctests clean up)
- AC-04.6 (non-test) Each remaining `async: false` carries a reason comment, or the module is `async: true` -- evidence: grep over test/ -- satisfied: no
- AC-04.7 `config/.env` no longer overrides shell-exported config vars during config evaluation: an env var exported by the developer or CI wins over the checked-in dev default, and the resolution path is identical on a fresh clone (which has no `config/.env`)

### WP-05 -- Surface and dependency pruning (status: TODO)

- AC-05.1 Every dependency removal carries positive downstream evidence and is proven by the WP-06 arca_cli rebuild; **the default is KEEP**. In-repo non-reference is not grounds for removal (hv ruling on the dependency retraction: unreferenced-here over public surface means untested contract surface, not dead surface). A dep with no downstream evidence either way stays, and gets a note in impl.md rather than a deletion
- AC-05.2 Test backdoors (`{:reset_for_test, ...}`, `{:reset_to_dormant, ...}`) are out of production modules, with equivalent test control via supervised lifecycle
- AC-05.3 (ruling R3) The CLI ruling is executed: either a single dispatch path through the Optimus spec in an extracted module, or the escript is removed; no unreachable command spec remains
- AC-05.4 (non-test) One CI workflow, matrix per ruling R6 -- evidence: .github/workflows/ diff + green run -- satisfied: no
- AC-05.5 (non-test) Cruft removed from version control: `AGENTS.md.bak`, `.backup/`, committed `.arca_config/` artifacts, debug scripts (or an explicit keep-ruling recorded) -- evidence: git rm list in impl.md -- satisfied: no
- AC-05.6 The facade module contains delegation and documentation only; CLI/conversion/watch-loop logic lives elsewhere; critic-elixir pass on changed files is clean at severity >= warning

### WP-06 -- Downstream verification and release (status: TODO)

- AC-06.1 (non-test) vc's rebuild of arca_cli against the final arca_config passes its full suite; failures triaged to migration notes or fixed here -- evidence: vc report cited in impl.md -- satisfied: no
- AC-06.2 (non-test) Migration notes list every breaking change with the replacement API, including the three arca_cli defensive strata now removable (error-prose matcher, Server.delete bypass, get_config_location shim) -- evidence: CHANGELOG/migration doc -- satisfied: no
- AC-06.3 (non-test) CHANGELOG + version bump per ruling R5 + tag by hv -- evidence: tagged release -- satisfied: no
- AC-06.4 (non-test) `usage-rules.md` (or successor consumer doc) carries actual arca_config API guidance for consumer LLM sessions -- evidence: file content review -- satisfied: no

## Acceptance Tests

### ST-level

- AT-00.1 test/config/consumer_contract_test.exs::"downstream-relied-upon surface is pinned" -- covers AC-00.4 -- status: to-write (red-first, pending hv approval of AC-00.4)
- Coverage: AC-00.1/.2/.3 are non-test with evidence on the AC line; AC-00.4 covered by AT-00.1

### WP-01

- AT-01.1 test/config/server_test.exs::"put returns error and preserves state on unwritable location" -- covers AC-01.1 -- status: to-write (red-first)
- AT-01.2 test/config/server_test.exs::"put!/delete! raise on persistence failure" -- covers AC-01.2 -- status: to-write (red-first)
- AT-01.3 test/config/server_test.exs::"failed load surfaces as load error not key-miss" -- covers AC-01.3 -- status: to-write (red-first)
- AT-01.4 test/config/cache_test.exs::"cache unavailability is distinct from key-miss" -- covers AC-01.4 -- status: to-write (red-first)
- AT-01.5 test/config/phase_based_test.exs::"failed override surfaces from load_config_phase" -- covers AC-01.5 -- status: to-write (red-first)
- AT-01.6 test/config/switch_location_test.exs::"switch to nonexistent path errors and preserves location" -- covers AC-01.6 -- status: to-write (red-first)
- Coverage: AC-01.1..6 each have an AT; none uncovered

### WP-02

- AT-02.1 test/config/server_test.exs::"every public write path registers exactly one write token" -- covers AC-02.1 -- status: to-write (red-first)
- AT-02.2 test/config/error_dialect_test.exs::"missing key shape is canonical across all entry points" -- covers AC-02.2 -- status: to-write (red-first)
- AT-02.3 test/config/facade_test.exs::"facade delete/delete!/get_config_location" -- covers AC-02.3 -- status: to-write (red-first)
- AT-02.4 test/config/map_test.exs::"Access.pop deletes through the write path" -- covers AC-02.4 -- status: to-write (red-first)
- AT-02.5 test/config/server_test.exs::"get_config single reply shape (no GenServer meck)" -- covers AC-02.5 -- status: to-write (red-first)
- Coverage: AC-02.1..5 each have an AT; none uncovered

### WP-03

- AT-03.1 test/config/notification_matrix_test.exs::"matrix: each channel fires once per covered path" -- covers AC-03.1, AC-03.2, AC-03.3 -- status: to-write (red-first)
- AT-03.2 test/config/file_watcher_test.exs::"watcher survives malformed JSON and recovers" -- covers AC-03.4 -- status: to-write (red-first)
- AT-03.3 test/config/file_watcher_test.exs::"external edit within post-write window is detected" -- covers AC-03.5 -- status: to-write (red-first)
- AT-03.4 test/config/server_test.exs::"ancestor get reflects nested put (cache coherence)" -- covers AC-03.6 -- status: to-write (red-first)
- Coverage: AC-03.1..6 covered (AT-03.1 covers .1/.2/.3); none uncovered

### WP-04

- AT-04.1 test/config/cfg_test.exs::"precedence chain end-to-end" -- covers AC-04.1 -- status: to-write (red-first)
- AT-04.2 test/config/cfg_test.exs::"config_domain deterministic without heuristic" -- covers AC-04.2 -- status: to-write (red-first)
- AT-04.3 test/config/cfg_test.exs::"location stable across file creation" -- covers AC-04.3 -- status: to-write (red-first)
- AT-04.4 test/support/isolation_check.exs::"suite leaves repo tree and env exactly as found" -- covers AC-04.5 -- status: to-write (red-first)
- AT-04.5 test/config/cfg_test.exs::"shell-exported config var beats the checked-in dev default" -- covers AC-04.7 -- status: to-write (red-first)
- Coverage: AC-04.1/.2/.3/.5/.7 test-covered; AC-04.4/.6 non-test with evidence on the AC line

### WP-05

- AT-05.1 test/config/facade_test.exs::"no test backdoor messages handled by prod modules" -- covers AC-05.2 -- status: to-write (red-first)
- AT-05.2 test/arca_config_cli_test.exs::"single dispatch path per R3 ruling" -- covers AC-05.3 -- status: to-write (red-first)
- AT-05.3 (gate) mix deps audit script asserting declared == referenced -- covers AC-05.1 -- status: to-write (red-first)
- AT-05.4 (gate) critic-elixir clean at >= warning on changed files -- covers AC-05.6 -- status: to-write (red-first)
- Coverage: AC-05.1/.2/.3/.6 covered; AC-05.4/.5 non-test with evidence on the AC line

### WP-06

- Coverage: all WP-06 ACs are non-test (vc-executed or hv-held); evidence named on each AC line
