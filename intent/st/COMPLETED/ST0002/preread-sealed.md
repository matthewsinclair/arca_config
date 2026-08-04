# SEALED -- Opus pre-read findings, arca_config, 2026-08-04

**DO NOT SHOW TO FABLE.** Written before the Fable cold audit of ST0002, to be opened only afterwards as a recall check on Fable's coverage.

Author: cc (Opus 5), arca_config session 797c6bb0. Produced from a full read of all 9 lib modules before the arca_cli handover note arrived, and before hv ruled that the analysis phase belongs to Fable. Sealing exists because a briefed audit is a confirmed audit -- the value of Fable's pass is that it clusters from raw evidence, and this file would supply the clusters.

Use afterwards to compute: what Fable found that I missed, what I found that Fable missed, and whether our independent clusterings agree.

Baseline at time of writing: `mix compile --force --warnings-as-errors` clean. `mix test` 128 passed (41 doctests, 87 tests), 1.4s. HEAD 9925115. `git diff 8b30615..HEAD -- lib/ mix.exs` is empty (drift is mix.lock only).

## Confidence key

| Level      | Meaning                                                            |
| ---------- | ------------------------------------------------------------------ |
| CONFIRMED  | Read directly from source; the claim is a structural fact.         |
| HIGH       | Traced through the code but not executed; wants a red test.        |
| OBSERVED   | Mechanically measured (grep, git) with the command recorded.       |

## Findings

### F1 -- `Server.put/2` reports success on a failed disk write (CONFIRMED)

`server.ex:471` calls `write_config(new_config)` and discards the result. `write_file_with_logging/2` (`server.ex:731-740`) returns `:ok` on success and the return value of `Logger.error/1` -- also `:ok` -- on failure. `handle_call({:put, ...})` then replies `{:ok, value}` and commits `new_config` to state. On EACCES / ENOSPC / read-only dir, the caller is told the value persisted, in-memory state advances, and disk does not. IN-AG-NO-SILENT-001, IN-EX-CODE-005.

### F2 -- `Server.delete/1` has the same defect (CONFIRMED)

`server.ex:498` discards `write_config/1`'s result and replies `{:ok, :deleted}` at `server.ex:513`.

### F3 -- Highlander: two divergent implementations of nested get/put/write (CONFIRMED)

- `Cfg`: `get/1` (`cfg.ex:388`), `put/2` (`cfg.ex:461`), `update_nested_config/3` (`cfg.ex:508`), `write_config/2` (`cfg.ex:517`).
- `Server`: `get_in_nested/2` (`server.ex:635`), `put_in_nested/3` (`server.ex:650`), `write_config/1` (`server.ex:701`).

They are not equivalent. `Cfg.write_config/2` does **not** call `FileWatcher.register_write/1`; `Server.write_config/1` does (`server.ex:716-717`). So a write through `Cfg.put/2` is seen by the FileWatcher as an external change and triggers a reload plus a full callback notification. Two paths for one concern, with a behavioural fork. IN-AG-HIGHLANDER-001, IN-EX-CODE-006.

### F4 -- Four distinct not-found dialects (CONFIRMED)

| Dialect                              | Site                          |
| ------------------------------------ | ----------------------------- |
| `{:error, :not_found}`               | `cache.ex:38`, `server.ex:275` |
| `{:error, "Key not found"}`          | `server.ex:639`, `server.ex:644` |
| `{:error, "'#{key}' not found"}`     | `cfg.ex:399`                  |
| `{:error, "No such property: ..."}`  | `cfg.ex:362`                  |

The handover note reported two. Which of these actually surface through the `Arca.Config` facade is an open question -- arca_cli is text-matching the prose form at `lib/arca_cli.ex:1086-1098`, so the answer is load-bearing downstream.

### F5 -- Cache ancestors go stale after a nested put (HIGH)

`handle_call({:put, key_path, value}, ...)` caches the leaf only: `Cache.put(key_path, value)` at `server.ex:474`. Ancestor entries written by `flatten_and_cache/2` (`server.ex:746-763`) still hold pre-update maps, and `normal_get/1` (`server.ex:44`) consults the cache first. So after `put("db.host", "x")`, `get("db")` should return the stale parent map. `delete` uses `Cache.invalidate/1`, which clears descendants (`cache.ex:125-140`) but not ancestors either. Wants a red test before it is asserted.

### F6 -- FileWatcher crashes into permanent dormancy on malformed JSON (HIGH)

`file_watcher.ex:185` hard-matches `{:ok, _config} = Arca.Config.Server.reload()`. `reload` reaches `Cfg.load/1`, whose decode-failure path returns `{:error, "Error parsing config at position: ..."}` (`cfg.ex:161-163`). MatchError, crash, `:one_for_one` restart, and `init/1` (`file_watcher.ex:105-109`) comes back with `watching: false` and schedules no timer. One bad hand-edit of the config file disables watching for the rest of the process lifetime, silently. Externally-edited config is exactly the case this module exists to serve.

### F7 -- FileWatcher swallows external edits inside the post-write window (HIGH)

In `handle_info(:check_file, ...)` (`file_watcher.ex:166-213`), a detected change is suppressed whenever `write_token` is non-nil (`file_watcher.ex:183`) regardless of what caused it, and `last_info` is then advanced to `current_info` (`file_watcher.ex:196`). A genuine external edit landing between our write and the next 5s tick is therefore dropped and never re-detected. Separately, the token's *value* is never compared to anything -- only its nil-ness is read -- so `register_write/1`'s documented "unique token identifying the write operation" (`file_watcher.ex:26-37`) is a contract nothing honours.

### F8 -- Cache's defensive rescue cannot fire (CONFIRMED)

`cache.ex:56-64`, `73-81`, `93-101` wrap `GenServer.call` in `try/rescue _error -> {:ok, ...}`, commented "Return success even if server is down for tests". A call to a dead or unregistered GenServer **exits**; it does not raise. `rescue` catches exceptions only. The clause cannot fire for its stated purpose. It is simultaneously a No-Silent-Errors violation in intent and inert in practice -- production code shaped by a test worry that it does not address.

Related: `Cache.get/1` (`cache.ex:34-43`) rescues `ArgumentError` from `:ets.lookup` on a missing table, making "cache absent" indistinguishable from "key absent".

### F9 -- The Optimus subcommand spec is unreachable (CONFIRMED)

`main/1` (`arca_config.ex:490-510`) intercepts `["set", ...]`, `["get", ...]`, `["list" | _]` and `["watch", ...]` in a `case` before Optimus is ever consulted. Consequently `process_command/1`'s four subcommand clauses (`arca_config.ex:573-587`) are dead; only the `_` "Invalid command" fallback at `arca_config.ex:589` can fire. The ~55-line subcommand block inside `cli_spec/0` (`arca_config.ex:526-569`) is decorative. Two dispatch paths for the same four commands, one of which always wins. This also bears on F10: the only non-Jason dep in live use is reached solely through this path.

### F10 -- 8 of 13 declared deps have zero references (OBSERVED)

`grep -rw <Module> lib/ test/`, with `test/support` inside the test compile path (`mix.exs:20`):

| Dep                              | References in lib/ + test/ |
| -------------------------------- | -------------------------- |
| `ok`, `owl`, `ucwidth`, `pathex` | 0                          |
| `table_rex`, `elixir_uuid`       | 0                          |
| `castore`, `dotenv`              | 0                          |
| `optimus`                        | 2 (both in `arca_config.ex`) |
| `jason`                          | 35                         |

`certifi` has no obvious module reference either. This confirms the handover's unverified lead and enlarges it. The `optimus` fork carries `override: true` (`mix.exs:34`), forcing it onto every consumer in the tree, and its only use is the CLI path that F9 shows is half dead. Caveat: a dep can be needed at runtime without a compile-time module reference; `castore`/`certifi` are the plausible cases and want checking rather than assuming.

### F11 -- `delete/1` is not re-exported on the facade (CONFIRMED)

Public on `Server` (`server.ex:133`, `server.ex:151`), absent from `Arca.Config`. Corroborates handover seed defect 2; found independently.

### F12 -- `Access.pop/2` never pops (CONFIRMED)

`map.ex:152-156` returns the config unchanged. `get_and_update/3`'s `:pop` branch (`map.ex:146-149`) likewise, commented "Since we can't really delete keys" -- but `Server.delete/1` exists. The Access behaviour contract is violated silently, and the comment's premise is false.

### F13 -- Dead clause and partial match in `notify_external_change/0` (CONFIRMED)

`server.ex:357-361` matches `{:ok, conf}` then `conf when is_map(conf)`. `handle_call(:get_config, ...)` (`server.ex:429-431`) replies with a bare `state.config` map, so the first clause is unreachable. There is no catch-all, so a non-map reply would raise CaseClauseError.

### F14 -- Env-var overrides cannot express underscored keys (CONFIRMED)

`apply_env_overrides/0` (`arca_config.ex:186-190`) does `String.downcase() |> String.replace("_", ".")`, so `<PREFIX>_CONFIG_OVERRIDE_LLM_CLIENT_TYPE` resolves to `llm.client.type`, never `llm_client_type`. The documented pattern offers no escape, and underscored top-level keys are the repo's own idiom (`intent/wip.md` cites `llm_client_type`). The `put/2` result at `arca_config.ex:196` is also discarded, so a failed override is silent.

### F15 -- Thin Coordinator violation in the facade module (CONFIRMED)

`arca_config.ex` is 690 lines carrying three roles: `Application` callback (`arca_config.ex:116-131`), public API facade, and the whole escript CLI -- Optimus spec, command handlers, `watch_loop/1` (`arca_config.ex:644-658`), and `try_convert_value/1` (`arca_config.ex:660-689`). IN-AG-THIN-COORD-001.

### F16 -- `Cfg` is called legacy but is the live loader (CONFIRMED)

Aliased `LegacyCfg` at `server.ex:16` and called on every load, reload and switch path, while remaining a documented public API with its own doctests. Ownership is ambiguous, which makes "is this dead?" unanswerable without a ruling.

### F17 -- Every test module is `async: false` (OBSERVED)

All 9. The root cause is architectural, not test laziness: config location resolves through process-global `System.put_env`, so parallel tests would fight over it. IN-EX-TEST-003 wants this to be a deliberate, recorded decision. Nothing to fix in the tests until the env-var coupling is addressed.

### F18 -- `meck` mocks own modules and `GenServer` itself (OBSERVED)

`map_test.exs:119` (`Arca.Config.Server`), `file_watcher_test.exs:109` (`Arca.Config.Server`), `server_test.exs:356` (`GenServer`, `[:passthrough]`). IN-EX-TEST-006 permits mocking only at external boundaries. Mocking `GenServer` is the sharpest case.

### F19 -- `Arca.Config.Map` has none of Map's semantics (CONFIRMED)

The struct is empty (`map.ex:18`), so it is a pure façade over global `Server` state. `put/3` returns the same struct; two "different" instances are the same thing; there are no value semantics despite the name and the docs. Arguably intentional, but undocumented as a caveat.

### F20 -- Notification is deferred behind the reply (CONFIRMED)

`server.ex:480` sends `{:notify_paths, ...}` to self, so `put/2` returns to the caller before subscribers are notified. Any test or consumer that puts and then expects a `{:config_updated, ...}` message is racing. Also, `Process.send/3` with `[:noconnect]` to `self()` is a curious choice worth a sentence of justification.

### F21 -- Version claims disagree (OBSERVED)

`mix.exs:8` declares `elixir: "~> 1.18"`; commits `8b30615` / `0ef66e7` claim the move to Elixir 1.20. `mix.exs:5` says `version: "0.2.0"`.

### F22 -- Repo cruft (OBSERVED)

`AGENTS.md.bak` and `.backup/` are present at the repo root.

### F23 -- `Arca.Config.get_config_location/0` has never existed (OBSERVED)

`git log -S "get_config_location" --all` returns nothing; absent at pinned `8b30615` and at HEAD. arca_cli hard-matches it at `cli_command_helper.ex:350`. Not arca_config's defect and not mine to fix, but it removes one row from the handover's blast-radius table.

## My clustering (the most contaminating part -- compare against Fable's, do not supply it)

Four patterns, arrived at independently of ST0011's archetypes, which I have not seen:

1. **Success is reported without being established.** F1, F2, F8, F14. Every write-shaped operation returns `{:ok, ...}` on a path where the effect may not have occurred. The failure is always logged and never returned.
2. **One concern, two implementations, silently divergent.** F3, F4, F9, F11, F12. In each case both halves exist, one is favoured, and the disfavoured half is neither removed nor kept correct.
3. **The watcher's correctness rests on timing it does not control.** F6, F7, F20. A 5s poll, a boolean token, a hard match, and a deferred send. Each is individually small; together they mean external-change detection is best-effort and fails silently in both directions.
4. **Test-shaped concessions have leaked into production code.** F8's rescue clauses, `handle_call({:reset_for_test, ...})` (`server.ex:434-437`), `handle_info({:reset_to_dormant, ...})` (`file_watcher.ex:160-164`), and the env-var coupling behind F17. The library carries test scaffolding in its shipped surface.

The candidate anchor contract I would have proposed, for comparison against whatever the findings actually support: **every public function's return value is a truthful account of what happened on disk.** That subsumes cluster 1 outright and gives clusters 2 and 3 a boundary to be judged against.

## Coverage I did not attempt

Not read: `test/support/config_test_support.ex` beyond a grep, the 9 test files in full, `README.md`, `usage-rules.md`, `AGENTS.md`, `config/`, `scripts/`, `.github/`. Not run: dialyzer, credo, the `critic-elixir` pass, any red test proving F5/F6/F7. Not checked: the sibling repos (`arca_id`, `arca_dbutils`, `arca_notionex`, `arca_doc`, `arca_optimus`) for `function_exported?` / `Code.ensure_loaded?` probes against `Arca.Config`, which the handover flags as mandatory before retiring any public symbol.
