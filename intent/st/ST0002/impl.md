# Implementation - ST0002: Fable review of arca_config base code

## Implementation

Baseline (2026-08-04, HEAD 9925115): `mix compile --force --warnings-as-errors` clean; `mix test` 128 passed (41 doctests, 87 tests). lib/ 2,771 LOC over 9 files; test/ 2,112 LOC over 9 files + support.

Probe artifacts: `probes/` (scripts + verbatim output), durable in this ST directory; results transcribed into design.md's ledger (probes P1/P2/P3/P3b/P5/P7).

### WP-01 Truthful returns (AR-1) -- landed 2026-08-04

Six red-first ATs written before any `lib/` change; each failed for exactly the defect its ledger row describes (put returned `{:ok, "PhantomApp"}` with `:eacces` logged, switch to a nonexistent path returned `{:ok, previous}`, a dead cache read as key-miss, and so on). After: **134 passed (41 doctests, 93 tests)** -- 128 baseline + 6 net new -- deterministic across seeds 1, 42, 7777, 12345, 314159, 854443, 982300, 2718; `mix compile --force --warnings-as-errors` clean; `git status --porcelain` unchanged by a test run; suite output is dots only.

As-built, by finding:

- **AF-01/AF-02** `write_config/1` returns `:ok | {:error, reason}` (a `with` over `ensure_config_exists` then `File.write`, still logging at error level). `handle_call({:put,…})` and `({:delete,…})` branch on it: on failure they reply `{:error, reason}` and advance neither server state, cache, nor notifications. `write_file_with_logging/2` -- whose failure branch returned `Logger.error/1`'s `:ok`, the root of the archetype -- is gone.
- **AF-03** `apply_env_overrides/0` maps each override through `apply_env_override/2`, collecting `{key_path, reason}` failures into `{:error, {:env_overrides_failed, failures}}`. `load_config_phase/0` aggregates via `phase_result/2`; a load failure dominates an override failure. The duplicated start-watching-and-apply-overrides pair across both branches collapsed into one path (Highlander).
- **AF-04** the on-demand load in `handle_call({:get,…})` became `ensure_loaded/1` + `reply_to_get/2`. A failed load now surfaces its own reason and stays `loaded: false`, so a later read retries rather than reporting "Key not found" for every key forever.
- **AF-05** the cache's fabricating `rescue` clauses are gone. `Cache.get/1` distinguishes `:not_found` from `:cache_unavailable`; `put`/`clear`/`invalidate` route through `call_cache/1`, which catches the **exit** a dead GenServer actually produces (the old `rescue` could never fire for its stated purpose) and returns `{:error, :cache_unavailable}`.
- **AF-06 (ruling R4)** `Cfg.load/2` takes `bootstrap: true`; enoent maps to `{:ok, %{}}` only for that caller, which is `handle_call(:load_config,…)` -- the documented first-run path. Every other loader (`reload`, `switch_config_location`, on-demand get) now gets `{:error, "Failed to load config file: enoent"}`. `switch_config_location/1`'s failure branch also rebuilds the cache from the previous config, so the old location stays fully live, not just env-var-live.

Decisions taken while building, for the record:

- **Error reasons stay a mixed dialect.** WP-01 propagates the raw posix atom (`:eacces`) for write failures and leaves the existing strings alone; unifying them is WP-02 under ruling R1, which needs vc's concurrence. `format_reason/1` was added so the bang functions can raise on any reason shape -- binaries pass through unchanged (so `get!`'s existing message text, which arca_cli text-matches, is byte-identical), anything else is inspected. Without it a tuple reason would crash the raise that reports it.
- **A cache failure does not fail a write that landed.** The contract of `put/2` is disk persistence; the cache only accelerates reads in front of it, and a cache that is down has no ETS table at all, so it cannot serve a stale value. `report_cache_result/1` reports the degradation at warning level and returns `:ok`. This is not the discarded-return pattern: the effect being reported did happen.
- **`rebuild_cache/1`** replaced four `Cache.clear(); build_cache(…)` pairs, and checks availability once per rebuild rather than once per key, so an unavailable cache costs one log line instead of N.

Breaking changes for the WP-06 migration notes: `put/2`, `delete/1`, `put!/2`, `delete!/1` can now fail where they previously could not; `switch_config_location/1` to a location with no config file now errors; a `get` before any successful load reports the load error rather than "Key not found" (this one changes the string arca_cli's `setting_error/2` greps, so it needs the R1 dialect on both sides).

Deferred, deliberately: the write token is registered before the write and stays registered when the write fails (a failed write can suppress a real external change for one window) -- that is AC-03.5's territory, WP-03. `flatten_and_cache/2` still discards per-key `Cache.put` results, now guarded by `rebuild_cache/1`'s single availability check; WP-03 rewrites it for AC-03.6.

## Changed-tests ledger

Every test changed because it asserted a defect gets a row here (AC-00.3). Flag each to vc.

| Test                                                                    | Asserted defect                                                                                                             | Change                                                                                                                          | WP    |
| ------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------- | ----- |
| `switch_location_test.exs` "handles error when switching to non-existent location" | AF-06. Asserted `{:ok, _}` on a switch to a nonexistent path, with the comments narrating the drift ("Actually succeeds with empty config") | Replaced by AT-01.6 "switch to nonexistent path errors and preserves location": asserts the error, plus config, cache and env vars still on the old location | WP-01 |
| `switch_location_test.exs` "handles switch with only path change"        | Same defect, second-hand: relied on location2 having no `config.json` so the switch would "succeed" into emptiness            | Intent preserved (a path-only switch retains the filename); the test now writes a `config.json` into location2 and asserts it reads back | WP-01 |
| `switch_location_test.exs` "can clear config location with nil values"   | Not a defect assertion -- collateral from R4. Clearing to a default with no config file is now a failed switch                | Points the generic env pair at location3 first, so clearing the app-specific pair falls through to a real file; also now asserts the fallthrough resolved | WP-01 |
| `cfg_test.exs` "load nonexistent configuration file (returns empty config)" | AF-06 at source: the test name asserted that any load of a missing file succeeds with `%{}`                                  | Renamed "(fails, and bootstraps empty)"; asserts `{:error, "…enoent"}` for the ordinary caller **and** `{:ok, %{}}` for `bootstrap: true`, pinning both halves of R4 | WP-01 |
| `arca_config.ex` `switch_config_location/1` doctest                      | AF-06 in documentation form: switched to `/tmp/test_config` with no file there and showed it succeeding                       | Creates the target location first, asserts the value reads back, restores and cleans up; doc now states that switching to a location with no config file errors | WP-01 |
| `cfg.ex` `load/1` doctest                                                | Hygiene, exposed by R4: it deleted `System.tmp_dir!()/config_test.json` -- the shared fixture the module's ambient location points at -- and deleted env vars it did not set | Rewritten to use `load/1`'s explicit-path form on its own file: touches no env var, creates and removes exactly one file        | WP-01 |
| `cfg_test.exs` module setup                                              | Hygiene, exposed by R4: `setup_all` established the config location once, and several doctests then deleted the env var, leaving the rest of the module pointed at nothing | `setup_all` -> `setup` so the location is re-asserted per test. Also captures and restores the tracked repo-tree `.arca_config/config.json` instead of removing it | WP-01 |

Two of those rows are hygiene rather than defect-assertions, and both were invisible before ruling R4: while a load from a nonexistent location reported success with an empty config, a test that destroyed the location it depended on still passed. The suite was green over the top of them. The wider isolation sweep is AC-04.5 (WP-04); these are only what WP-01's change made visible.

Remaining known-in-advance candidates: map_test.exs:174-180, server_test.exs:341-375, file_watcher_test.exs:73-104, cfg_test.exs:99-109, auto_config_test.exs theatre tests.

Test-output discipline (hv, 2026-08-04): suite output is dots only. The `Logger.error` on a failed config write is necessary in production, so the tests that provoke it wrap the call in `ExUnit.CaptureLog.capture_log/1` and assert the message -- the operator-visible report is now pinned by test rather than printed as noise.

## Public-symbol removal log

Per AC-00.1: each retired public symbol gets a row with the fleet-probe evidence re-run at removal time.

| Symbol                                | Probe result | vc ack |
| ------------------------------------- | ------------ | ------ |
| (none yet)                            |              |        |

## Technical Details

- Commit discipline: per-WP batches behind compile + test gates; no `--no-verify`.
- The `register_change_callback/2` tripwire (arca_cli liveness proxy) must survive every WP until arca_cli migrates. See info.md context.

## Challenges & Solutions

(To be filled as remediation proceeds.)
