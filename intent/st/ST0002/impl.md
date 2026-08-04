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

### WP-03 Notification and watcher coherence (AR-3) -- landed 2026-08-04

Twelve ATs red first (ten in a new `notification_matrix_test.exs`, plus the two watcher ones), each failing for its ledger defect -- including the watcher's `MatchError` on a hand-broken file and the stale ancestor map from probe P2. After: **147 passed (41 doctests, 106 tests)**, deterministic across eight seeds, compile clean, dots-only output, tree unchanged by a run.

The matrix is in design.md and is the substance of this WP; it still needs hv's explicit yes. As-built by finding:

- **AF-17** one notification path for all five mutation events, replacing three divergent ones. Per-key subscribers are computed by diffing the value at each *subscribed* path rather than walking the written path's ancestors -- cheaper when nobody listens, and it reaches the subscriber whose value changed because an ancestor was replaced, which the ancestor walk could not see. 1-arity callbacks now fire on every path, not only external. The 0-arity double-fire is gone: the watcher no longer calls `reload` **and** `notify_external_change`; the reload is the event.
- **AF-18** the watcher's `{:ok, _} = Server.reload()` is now a `case` that logs a parse failure, keeps the last good config, and keeps watching. One malformed hand-edit used to raise a MatchError and restart it into permanent silent dormancy with no timer.
- **AF-19** the suppression window is gone, not patched. Self-notification is prevented by comparing configurations: a write we made produces a config identical to the one in memory, so it raises no event. Nothing is suppressed, so nothing can be lost in the window. `register_write/1` is kept and still records the token, now documented as diagnostic; whether it survives is WP-05's call under AC-05.1's default-KEEP.
- **AF-20** a successful put/delete rebuilds the cache from the new config instead of writing the leaf and leaving every ancestor stale. A full clear-and-rebuild per write is O(config) where the old code was O(1), which is the right trade next to a file write, and it makes the whole class of staleness unreachable rather than fixing the one path probe P2 found.
- **AF-21** subscriber messages are sent before the call returns instead of being deferred behind the reply, so put-then-expect-message no longer races. Callbacks stay asynchronous by design (below), which is documented.
- **AF-22** a `:check_file` already in the mailbox when watching stopped no longer re-arms the timer: the dormant clause does not reschedule, so a stopped watcher stays stopped.

Decisions taken while building:

- **Callbacks run off the server process**, via a supervised Task added to the tree. Widening the matrix is what made this necessary: 1-arity callbacks previously only ever ran from the watcher's process, and firing them inside `handle_call({:put,…})` would deadlock any callback that reads or writes config. Two tests pin that surface -- a callback that reads back, and a callback that writes a derived value.
- **The no-change-no-event rule was scoped, not applied uniformly.** It first broke two tests asserting that a bare `reload/0` notifies. Those tests are the only written record of that contract, so the rule was narrowed to writes and the reload contract kept. `Server.reload_external/0` was added for the watcher. See the design.md matrix.

Breaking changes for WP-06's migration notes: 1-arity callbacks now fire on put/delete/reload/switch, not only on external edits; 0-arity callbacks fire once rather than twice per detected external change; per-key subscribers now fire on reload/external/switch and no longer fire when the value did not change; callbacks are asynchronous, so a callback may not have run when `put/2` returns.

### WP-04 Location model (AR-4) -- landed 2026-08-04

Five ATs red first. After: **152 passed (41 doctests, 111 tests)** across seven seeds, compile clean, dots-only output, and -- for the first time in this thread -- a suite that provably leaves the working tree as it found it.

- **AF-26** the domain heuristic is gone. `config_domain/0` is `Application.get_env(:arca_config, :config_domain, :arca_config)`. The heuristic walked `$callers` and then took the first non-system entry from `started_applications/0`: probe P1 resolved it to `:elixir_uuid`, and the red AT resolved it to `:ex_unit`. Same defect, different answer each time it was asked.
- **AF-25** `config_file/0` is `config_pathname/0` joined to `config_filename/0`, expanded. The existence flip -- home-if-it-exists, else local -- is gone, so the answer no longer changes when a file appears. `local_config_pathname/0` is kept and documented as not part of resolution; retiring it is WP-05's call under AC-05.1's default-KEEP.
- **AF-28** every tier of `config_pathname/0` is expanded the same way. Values from environment variables used to be returned verbatim so that a test asserting string identity against a trailing slash would pass.
- **AF-23, AF-24** the README's precedence table now matches the resolver and `Cfg`'s moduledoc line for line, states that domain-specific beats generic, and says the default is CWD-relative rather than `~/`. The `.env` section says plainly that it is this repository's own dev setup, not a library feature.
- **AF-40 (AC-04.7)** `config/dotenv.exs` treats each line as a default: a variable already exported by the shell or set by CI wins. The AT runs the real script against a `.env` of its own in a temporary working directory.
- **AF-27, AF-29, AF-30, AF-31** the suite no longer escapes. `test_helper.exs` gives the whole run a disposable config location, takes a baseline of the working tree, the config env vars, the `:arca_config` application settings and a set of known escape paths, and fails the run on drift. Facade doctests no longer set `ARCA_CONFIG_PATH`/`FILE` at all (the suite location makes the plumbing unnecessary, and it reads better as documentation). Superset-restore is replaced by exact restore. Nothing writes into the repository.
- **AF-15 tail** one version string: `config.exs`'s copy removed, the CLI spec reads `Application.spec(:arca_config, :vsn)`, README's two install blocks reconciled.

**The isolation guard earned its place immediately, and caught me being wrong.** After fixing what I thought was the last leak, the suite was green across six seeds -- and the guard still reported `.test_app/` appearing in the repo. The seeds were green only because the directory already existed at baseline: a leak hiding behind the residue of the previous leak. Bisecting per file found two more unrestored mutations (`auto_config_test` left the config domain as `:test_app` for the rest of the run; `server_test`'s `put/2` block switched domain without pointing the new domain anywhere, so resolution fell to `.test_app/` in the working directory). Both are now restored, and `:arca_config`'s application settings joined the baseline so that class cannot hide again.

Breaking changes for WP-06's migration notes: a consumer that never set `:config_domain` and relied on auto-detection now gets `:arca_config` -- the moduledoc already said setting it explicitly was mandatory, and the heuristic's answer was never stable enough to depend on; `config_file/0` no longer falls back to the local path when the configured file is absent; `config_pathname/0` returns an expanded absolute path.

### AC-00.4 consumer contract + AC-02.3 facade completion -- landed 2026-08-04

The first thing built after hv ratified AC-00.4, and the instrument the rest of the thread leans on. Suite **167 passed (48 doctests, 119 tests)** across five seeds; no drift.

`test/config/consumer_contract_test.exs` (AT-00.1) pins every call arca_cli makes into this library, each assertion carrying the arca_cli `file:line` that makes it. It is deliberately mostly-green: a tripwire, not a feature test. WP-02 rewrites the error dialect and WP-05 removes surface, and this module is what turns "we broke our consumer" from a WP-06 discovery into a local failure at the moment of the change.

- The **liveness tripwire is now a test**. `register_change_callback/2` has zero callers in arca_config *and* zero callers in arca_cli -- `arca_cli.ex:129` only asks whether it exists, and if the answer goes false every `save_settings` silently stops persisting. A call-graph search cannot find that consumer. Deleting the symbol now fails our suite.
- **`get_config_location/0` was the one red.** It has never existed in any commit, yet arca_cli's testing helper documents it as the way to inspect a temp config (`cli_command_helper.ex:350`). That is documentation, not a live call site -- **the handover note's claim that arca_cli hard-matches it at runtime was wrong**, and nothing raises today. The obligation is real regardless: arca_cli tells its users the function is there.
- **The error dialect is now pinned as arca_cli reads it.** `arca_cli.ex:1080-1092` classifies a missing setting with three clauses -- bare `:not_found`, a binary containing "not found", and a generic fallback. We return `{:error, "Key not found"}`, so arca_cli takes clause two. The proposed R1 shape matches none of the accepting clauses, so it degrades (does not crash) to `cannot read setting X: {:config, :not_found, [...]}`. R1 is therefore a visible, deliberate break with a test that must be changed and ledgered when WP-02 lands it.
- **`switch_config_location/1`'s contract is the round-trip**, not the shape: `cli_command_helper.ex:500` passes a keyword list and matches `{:ok, previous}`, and `:509` feeds that same value straight back to restore.

AC-02.3 closed the red: the facade gained `delete/1`, `delete!/1` (both already on `Server`, absent from the facade) and `get_config_location/0`.

`get_config_location/0` returns a **map**, not the keyword list `switch_config_location/1` trades in, and the difference is deliberate. That function returns the *previous environment variables*, whose values may be nil precisely because nothing was set; a resolved location fed back into it would pin a location that was previously free to move. Different concepts get different shapes so the mistake is not available.

It reports `:path`, `:file`, `:config_file`, and a `:source` map keyed by `:path` and `:file` -- each of the two resolves independently through the same four tiers, so a single source atom would have been a lie whenever they differed. `source` is the answer to the question that cost arca_cli months: its isolation set `ARCA_CONFIG_PATH` across nine files and never took effect, because the domain-specific variable outranks it. That situation now reports `:env_domain` and ends the guessing.

**Highlander applies to the source, not just the value.** Deriving `:source` from a second copy of the `||` chain would drift from the resolution that actually happened the first time either changed. Instead `resolved_pathname/0` and `resolved_filename/0` hold the one ordered tier list and return `{source, value}`; `config_pathname/0` projects the value, `config_location/0` projects the source. `config_filename/0`'s `if String.contains?(filename, "/")` branch went with it -- `Path.basename/1` is a no-op on a bare filename, so the branch never did anything the call does not already do.

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

| `file_watcher_test.exs` "register_write prevents notification loops"     | AF-19. Registered a write token, then wrote *different* content by hand and asserted silence -- enshrining the suppress-everything window that lost real external edits | Replaced by "our own write is not re-notified as an external change": a real `put` is reported once, and the watcher's next tick raises nothing because nothing differs | WP-03 |
| `file_watcher_test.exs` "detects file changes and notifies the server to reload" | AF-17. Meck'd `Server.reload/0` **and** `notify_external_change/0` and asserted both were called -- that pair was the 0-arity double-fire | Rewritten against the real server, no meck: a real external edit raises exactly one event and the config reflects it | WP-03 |

| `cfg_test.exs` "config file path and name via env var"                  | AF-28. Asserted `System.get_env(var) == config_pathname()` with a trailing slash, which is *why* env-derived paths were left unexpanded while every other tier was expanded. It also left `/tmp/` and `bozo.json` in the environment | Asserts the expanded values (`/tmp`, `bozo.json`, `/tmp/bozo.json`) and restores both variables | WP-04 |
| `phase_based_test.exs` "system loads config from environment-specified paths" | Passed for the wrong reason: it asserts the *generic* env tier, which only works while the domain-specific tier is empty. The domain was being guessed as `:ex_unit`, so the variable it competed with was `EX_UNIT_CONFIG_PATH` and nothing set that | Clears and restores the domain-specific pair explicitly, so it tests the tier it claims to | WP-04 |
| `auto_config_test.exs` "explicitly tests directory setup and cleanup"    | AF-31. Called `setup_default_config/2` in the repository and asserted `.test_app/` appeared there -- which is why test_helper deleted that directory from three locations | Renamed "sets up a default config directory relative to the working directory"; runs in a temporary working directory and asserts the returned path | WP-04 |
| `server_test.exs` "correctly handles absolute paths when writing config" | Not a defect assertion: it configured the location via application config, the third tier, which this describe block's own env vars now shadow | Points the domain's environment variables at the absolute path instead | WP-04 |
| `test_helper.exs`                                                        | AF-31. Deleted `.test_app` from HOME, the working directory and the repo's parent, before and after every run -- removing the evidence of the escape it was documenting | Replaced by a baseline plus an after-suite drift check that fails the run, and a disposable config location for the whole suite | WP-04 |
| `cfg_test.exs`, `auto_config_test.exs`, `phase_based_test.exs`, `file_watcher_test.exs`, `server_test.exs` setups | AF-30. Restored env by superset (`System.put_env(System.get_env())`, which cannot delete), deleted variables they had not set, or left the config domain changed for the rest of the run | Capture-and-restore exactly, including `:config_domain` | WP-04 |

Two of the WP-01 rows are hygiene rather than defect-assertions, and both were invisible before ruling R4: while a load from a nonexistent location reported success with an empty config, a test that destroyed the location it depended on still passed. The suite was green over the top of them. The wider isolation sweep is AC-04.5 (WP-04); these are only what WP-01's change made visible.

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
