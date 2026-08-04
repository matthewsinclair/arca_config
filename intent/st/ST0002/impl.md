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

The matrix is in design.md and is the substance of this WP; hv ratified it on 2026-08-04, both rules included. As-built by finding:

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

### WP-02 partial: AC-02.1, AC-02.4, AC-02.5 -- landed 2026-08-04

The R1-independent half of AR-2. **AC-02.2 (the unified dialect) is the only part still waiting**, on vc's concurrence with the wire format. Suite **172 passed (48 doctests, 124 tests)** across six seeds; no drift.

**AC-02.1 -- there is now one nested implementation.** `Cfg.get/1`, `get!/1`, `put/2` and `put!/2` delegate to `Server`. They were a second nested get/put that loaded from disk on every read, wrote straight back to disk, and told nobody: the running server's in-memory config and the ETS cache both stayed on the old value until the file watcher happened to notice the file had changed, and a per-key subscriber never heard at all. `Cfg`'s private `update_nested_config/3` and `write_config/2` went with them.

**This is what AF-37 was actually asking.** `Cfg` was aliased `LegacyCfg` in `Server` while being the live loader on every load, reload and switch path -- which is why "is it dead?" had no answer. It was never one module: it is the **location and load authority** (`config_file/0`, `config_pathname/0`, `config_filename/0`, `config_location/0`, `env_var_prefix/0`, `load/2`), used by `Server`, `FileWatcher` and `InitHelper`, and pure over environment and filesystem so it answers with no server running. That half stays exactly where it is. The nested get/put half was the duplicate. The alias is gone and the moduledoc now says which is which.

The get/put family is **kept, not deleted**, per hv's standing lens: public, documented, doctested surface with no in-repo callers is untested contract surface. Delegation gives Highlander without removing anything a consumer might hold.

**AC-02.4 (ruling R7) -- `Access.pop/2` deletes.** It returned the value and left the key in place, with a comment stating that keys could not be deleted; `Server.delete/1` has always existed. `pop/2` now deletes through the one write path and `get_and_update/3`'s `:pop` branch calls `pop/2` rather than carrying its own copy of the lie. A key that is not set pops as `nil` and deletes nothing, matching `Access`.

**AC-02.5 -- the dead clause and the mock that reached it.** `notify_external_change/0` matched `:get_config` against both `{:ok, conf}` and a bare map; the handler only ever replies with the map. The test covering the unreachable clause **mocked `GenServer` itself** to fabricate a reply the runtime cannot produce -- mocking the runtime to reach code the runtime cannot reach (IN-EX-TEST-006). Both are gone, replaced by two tests against the real server.

Two dialect notes for R1. Delegation removed one of the four not-found dialects as a side effect -- `Cfg.get/1`'s `"'<key>' not found"` is now `Server`'s `"Key not found"`. That is Highlander doing it, not a dialect decision: `:not_found` from `Cache` and `remove_callback/1`, and `"No such property: ..."` from `inspect_property/1`, all still stand and are AC-02.2's to unify. `inspect_property/1` is deliberately untouched -- it is documented as *not* traversing nested paths, so it is not part of the nested lookup AC-02.1 covers, and it stays under AC-05.1's default-KEEP.

### WP-05 Surface and dependency pruning (AR-5) -- landed 2026-08-04

Unblocked by hv's ruling R3 (extract, not delete). Suite **188 passed (48 doctests, 140 tests)** across five seeds; compile clean; no drift.

**AC-05.3 (R3) -- one CLI, one dispatch.** `Arca.Config.CLI` now holds the command specification, the handlers and the watch loop. `main/1` used to open with a hand-written `case` on `argv` that caught `get`, `set`, `list` and `watch` before Optimus ever saw them, so the ~60-line specification and all four `process_command/1` clauses were unreachable (AF-11) -- the help text and the behaviour could drift apart indefinitely and nothing would notice. There is one path now, through the spec, and eight tests in `cli_test.exs` all go through `main/1`, so a spec that stopped matching fails them.

The `escript:` target is gone from `mix.exs`; `mix arca.config` stays and now points at `Arca.Config.CLI.main/1`. `Arca.Config.main/1` remains as a one-line delegate, which is the same move as `Cfg.get/1` delegating to `Server`: public surface kept, implementation unified.

Three fixes came with the extraction, since R3 chose extract-**and-fix**:

- The two printers are one. `get` printed a non-map with `IO.puts/1` and the watch loop printed it with `inspect/1`, and neither could show a list -- `IO.puts/1` treats a list as chardata, so a JSON array written by `set` and read back by `get` printed control characters. A string now prints as itself and everything else as JSON. Verified end to end against a real config file.
- An unquoted multi-word `set` value still works. The dispatch this replaces joined the trailing arguments with spaces; the specification's `value` takes one word, so the subcommand allows unknown args and rejoins them.
- `scripts/cli` no longer fails on a fresh clone. It ran `export $(cat ./config/.env ...)` unconditionally, and `cat` on a missing file aborted the command before mix ran.

**The extraction uncovered a shared helper, which is why the CLI could not simply be lifted out.** `try_convert_value/1` was a private helper of the CLI *and* the thing `load_config_phase/0` used to convert `ARCA_CONFIG_*` overrides -- two callers on opposite sides of the same module, neither of them owning it. It is now `Arca.Config.Value.from_string/1`, with doctests, called by both.

**AC-05.2 -- both test backdoors out, and one of them was a duplicate.** `{:reset_for_test, config}` in `Server` had zero callers: a backdoor in shipped code that nothing even used. `{:reset_to_dormant, pid}` in `FileWatcher` was a second copy of `stop_watching/0` that skipped cancelling the pending timer and answered asynchronously, so `phase_based_test` carried on before the watcher had actually stopped. Both gone; the test uses `FileWatcher.stop_watching/0`.

**AC-05.5 -- cruft out of version control.** Four committed `.arca_config/` artifacts (including a 2024 OAuth config and a `write_test.json` left by a probe), three March-2025 debug scripts that reproduced the path bug WP-04 fixed, and the commented-out `optimus` hex line. `.arca_config/` is now gitignored, so the developer copy `scripts/cli` writes cannot be committed again. `AGENTS.md.bak` and `.backup/` were already untracked and ignored -- nothing to remove from version control, recorded here so the AC is not read as unfinished.

**AC-05.4 -- one workflow.** `ci.yml` and `test.yml` ran nearly the same steps on overlapping triggers, so a change had to be made twice and a green tick meant whichever one you looked at. One workflow now, matrix per R6: 1.18.0/OTP 27, 1.18.4/OTP 28, and **1.20.2/OTP 29** to match the toolchain this library is actually developed on. Both workflows also set `ARCA_CONFIG_CONFIG_PATH: .arca_config` -- inside the checkout, which is how CI runs wrote into the repository. Removed: the suite points itself at a disposable location and fails on drift.

**AC-05.1 -- the dependency set is deliberate, not pruned.** As drafted, AT-05.3 was a gate asserting declared == referenced, which would have failed the build for every dependency with no in-repo call site -- the exact inference hv overruled, encoded as CI. `deps_audit_test.exs` instead names all thirteen with the reason each is kept, and fails when one is added or removed without saying which. Only `jason` and `optimus` carry direct in-repo evidence; `ok`, `castore`, `certifi`, `owl`, `ucwidth`, `pathex`, `table_rex` and `elixir_uuid` have none either way and stay under default-KEEP, for the WP-06 rebuild to settle.

**AC-05.6 -- the facade is delegation and documentation.** ~200 lines left it; `Optimus`, `watch_loop` and the conversion are all absent from it, asserted structurally in `production_surface_test.exs`. The Application callback and the start phase stay, because that is what the module is. **The critic-elixir pass this AC also requires has not been run** -- it needs a subagent, which is hv's call to authorise. AC-05.6 is not satisfied until it is.

**A five-seed sweep missed a real order-dependence, again.** After the AC-02.1 delegation the suite was green across six seeds; an unseeded run then failed `cfg_test`'s `get!` immediately. The cause was genuine: `Cfg.get/1` used to re-read the file on every call, so pointing the environment variables somewhere new was enough on its own, and it now delegates to the server, which holds one loaded configuration. Whether the test saw its own fixture depended on whether something earlier had reloaded. The module setup now loads the location it establishes. **This is a breaking change worth carrying to WP-06's migration notes**: moving the location behind the server's back and expecting reads to follow is the ambient-location behaviour AR-4 removed -- use `switch_config_location/1`, or `reload/0`.

### AC-02.2 the unified error dialect (ruling R1) -- landed 2026-08-04, WP-02 complete

hv delegated the wire format to the builder ("pick a sensible one"), so the decision and its consequences are recorded here rather than in a ruling. Nine of twelve ATs red first. Suite **200 passed (48 doctests, 152 tests)** across six seeds; no drift.

**The shape: `{:error, {:config, reason, detail}}`**, built and owned by `Arca.Config.Error`. `reason` is a machine-matchable atom that will not be reworded; `detail` is the key path for key-scoped failures and the underlying cause otherwise -- a posix atom, or the descriptive binary for a parse failure.

**Nothing is lost in the move**, which is what made the shape choosable at all. The prose that used to *be* the error is now the `detail`, so a parse failure still reports its position and token; it just is not the thing you have to pattern-match on any more.

Four dialects for one idea are gone: `"Key not found"` (Server), `"'<key>' not found"` (Cfg, already removed by AC-02.1's delegation), `"No such property: <name>"` (`inspect_property/1`), and the bare `:not_found`. Write failures moved with them -- WP-01 deliberately left `:eacces` raw, and this is the WP that owed the unification.

**The error now names the key the caller actually asked for.** `get_in_nested/2` recursed on the remaining suffix, so it could only ever have reported the segment it stopped on; the full path is threaded down the recursion as `asked_for`. `Arca.Config.get("database.host.deeper")` reports `["database", "host", "deeper"]`, not `["deeper"]`.

**Migration order: arca_config first.** 0.3.0 is a breaking release under R5, and the WP-06 rebuild is the gate -- arca_cli will not ship against 0.3.0 unrebuilt, so the window is closed by the same work that opens it. The consequence was measured rather than guessed: `setting_error/2` (`arca_cli.ex:1080-1092`) accepts a bare `:not_found` atom and any binary containing "not found"; the canonical tuple matches neither, so a missing setting renders through the generic clause as `cannot read setting X: {:config, :not_found, [...]}`. Message text on an error path, never a crash, and every `{:ok, _}` path is untouched.

**Two shapes deliberately kept**, both documented in `Arca.Config.Error` rather than left looking like misses:

- `Cache.get/1` keeps `{:error, :not_found}` and `{:error, :cache_unavailable}`. Its "not found" means *not cached*, which is not the claim *no such key* -- and the one layer that has to tell a cold cache from a missing key is the layer that reads the cache first.
- `Server.remove_callback/1` keeps `{:error, :not_found}`. A callback reference is not a configuration key and there is no key path to report.

**`format_reason/1` became `Error.message/1`** and moved out of `Server`: rendering an error is not the server's job, and the bang functions were the only callers. It stays total by construction -- a final clause accepting anything -- so reporting an error can never itself fail on the shape of the error it reports.

**The AT-00.1 tripwire fired, exactly as designed.** The consumer contract test asserted `reason == "Key not found"`; it now asserts the canonical tuple *and* that arca_cli 0.5.0's two accepting clauses do not match it. That second assertion is the migration debt written down: when the rebuild lands the clause, it should flip to the accepting branch.

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
| `map_test.exs` "pop works with Access.pop"                               | AF-16 (ruling R7). Asserted that `Access.pop` leaves the key in place, with the comment "Since we can't actually remove keys, the original should still be there" -- the implementation's own excuse, restated as the expectation | Replaced by AT-02.4 "pop deletes through the one write path", plus siblings for a missing key (pops `nil`, deletes nothing) and for `get_and_update`'s `:pop` branch | WP-02 |
| `server_test.exs` "handles both tuple and map responses from get_config" | AF-12. Asserted a reply shape the handler cannot produce, and reached it by `:meck.new(GenServer, [:passthrough])` -- mocking the runtime to cover code the runtime cannot reach (IN-EX-TEST-006) | Replaced by AT-02.5: two tests against the real server, one that `notify_external_change/0` dispatches the live config and reports `{:ok, :notified}`, one that `:get_config` answers with the config map itself. No mock | WP-02 |
| `phase_based_test.exs` watcher reset (setup + on_exit)                   | AF-33. Used the production module's test-only `{:reset_to_dormant, self()}` message, which left the pending timer running and answered asynchronously, so the test continued before the watcher had stopped | Calls `FileWatcher.stop_watching/0` -- the public API, synchronous, and it cancels the timer. The backdoor is deleted | WP-05 |
| `cfg_test.exs` module setup (second change)                             | Not a defect assertion -- collateral from AC-02.1. The setup established a location by setting env vars, which was enough while `Cfg.get/1` re-read the file per call; after delegation the server holds one loaded config, so whether a test saw its own fixture depended on whether something earlier had reloaded | Setup now calls `Server.reload()` after establishing the location. Found by an unseeded run *after* six seeds had passed | WP-05 |
| `consumer_contract_test.exs` "a missing key is reported in the dialect arca_cli classifies as not-found" | Not a defect assertion -- it pinned the *old* dialect on purpose, so that changing it would be visible. AC-02.2 changed it | Renamed "a missing key is the canonical shape, and arca_cli 0.5.0 will not classify it": asserts the canonical tuple and that neither of arca_cli's accepting clauses match, which is the migration debt written down. The tripwire firing here is the tripwire working | WP-02 |
| `server_test.exs` put/delete persistence-failure ATs (AT-01.1), `notification_matrix_test.exs` "a failed mutation notifies nothing" | Not defect assertions -- they matched `{:error, :eacces}`, the raw posix atom WP-01 deliberately left in place until R1 | Now match `{:error, {:config, :write_failed, :eacces}}`. Same failure, same intent, canonical shape | WP-02 |
| `server_test.exs` "failed load surfaces as load error not key-miss" (AT-01.3), `cfg_test.exs` load ATs, `switch_location_test.exs` AT-01.6, `phase_based_test.exs` AT-01.5 | Not defect assertions -- they matched load and write failures as binaries (`reason =~ "Error parsing config"`, `"Failed to load config file: enoent"`, `reason =~ "enoent"`) | Now match `{:config, :load_failed, :enoent}` and `{:config, :load_failed, detail}` with `detail =~ "Error parsing config"`. Strictly stronger: the cause is matched as data instead of grepped out of a sentence | WP-02 |
| `cfg.ex` `get/1`, `get!/1`, `put/2`, `put!/2` doctests                   | Not defect assertions -- collateral from AC-02.1. Each set two env vars, wrote a fixture into `System.tmp_dir!()`, then deleted both env vars, so a module whose location came from `setup` was left pointing at nothing for whatever ran next | Rewritten against the ambient suite location with no env plumbing at all, matching the facade doctests cleaned in WP-04. They read as documentation now rather than as fixture assembly | WP-02 |

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

| Symbol                                                    | Probe result                                                                                                                  | vc ack  |
| --------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------- | ------- |
| **No public symbol has been retired** through WP-01/02/03/04/05 | n/a -- nothing to probe                                                                                                    | pending |
| `Arca.Config.main/1` (WP-05)                              | KEPT as a delegate to `Arca.Config.CLI.main/1` rather than retired, precisely so the fleet probe is not needed                | n/a     |
| `Cfg.get/1`, `get!/1`, `put/2`, `put!/2` (WP-02)          | KEPT as delegates to `Server` rather than retired: public, documented, doctested surface with no in-repo callers is untested contract surface, not dead surface | n/a |
| `escript:` build target (WP-05, R3)                       | Not a module symbol. Fleet grep for `arca_config get\|set\|list\|watch` and `Arca.Config.main` across arca_cli, arca_id, arca_dbutils, arca_notionex, arca_doc: **zero hits**. The mix task, which is the documented path, is retained | pending |
| `{:reset_for_test, config}`, `{:reset_to_dormant, pid}` (WP-05) | Internal GenServer messages, not public API. `reset_for_test` had zero callers anywhere; `reset_to_dormant` had two, both in this repo's own test suite, migrated to `FileWatcher.stop_watching/0` | n/a |

The deletions this thread has made are of **private** functions (`Cfg.update_nested_config/3`, `Cfg.write_config/2`, `Server.write_file_with_logging/2`, `Server.get_notification_paths/2,3`, `Server.add_path_if_exists/3`, `Server.build_cache/1`), unreachable clauses, and repository files. Every public symbol is still exported.

## Technical Details

- Commit discipline: per-WP batches behind compile + test gates; no `--no-verify`.
- The `register_change_callback/2` tripwire (arca_cli liveness proxy) must survive every WP until arca_cli migrates. See info.md context.

## Challenges & Solutions

(To be filled as remediation proceeds.)
