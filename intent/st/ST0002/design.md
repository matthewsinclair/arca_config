# Design - ST0002: Fable review of arca_config base code

## Method and provenance

The analysis phase ran on Fable (hv switched the model mid-session, 2026-08-04). Provenance disclosure: an Opus pre-read of the 9 lib modules produced 23 sealed findings before the Fable pass (preserved verbatim at `preread-sealed.md` in this ST directory, unsealed once the Fable pass completed); the model switch happened inside the same session, so the sealed set was in the Fable context and this is a **verification-plus-extension audit, not a cold one**. Every claim below was re-derived from source (`file:line`) or executed (probe); sealed findings were confirmed, sharpened, or refuted rather than echoed. Provenance tags per finding: `[O]` Opus pre-read, `[F]` Fable pass (new), `[H]` arca_cli handover seed, `[X]` confirmed by executed probe.

Coverage: all 9 lib modules, all 9 test files + `test_helper.exs` + `test/support/config_test_support.ex`, README.md, usage-rules.md, mix.exs, config/*, both CI workflows, scripts/ listing, `.arca_config/` artifacts, git history probes, sibling-repo greps (arca_id, arca_dbutils, arca_notionex, arca_doc, arca_optimus), arca_cli call-surface verification. Not run: dialyzer, credo, critic-elixir (queued as WP gate tooling).

Execution probes: `probes/` in this ST directory (scripts + verbatim captured output in `probes/probe_output.md`), run 2026-08-04. Probe-attribution correction, on the record: the first P3 run (config file not pre-existing at the target) did not exercise the silent-write-failure path -- resolution flipped to the CWD-local default and the write landed in the repo root as `.arca_config/ro.json`, executing AF-25 instead. P3b pins resolution with a pre-existing file, then makes it unwritable: that is the AF-01 execution. Baseline: `mix compile --force --warnings-as-errors` clean; `mix test` 128 passed (41 doctests, 87 tests); HEAD `9925115`.

## Verdict in one paragraph

The library's core loop (load -> get/put via GenServer + ETS cache -> write-through JSON) is structurally sound and the suite is green, but the surface **lies in three directions**: to callers (writes report success whether or not disk was touched -- probe P3b returned `{:ok, "v"}` against a read-only file, left disk untouched, then served the phantom value from memory; the first P3 attempt was redirected by location-flip and silently wrote into the repo root instead), to subscribers (three notification channels fire on disjoint, undocumented subsets of the five mutation paths -- probe P5), and to readers (README documents the env-var precedence backwards; the inversion is what silently broke arca_cli's test isolation, their finding A22). Around that sit two parallel implementations of every core concern, a location model made of mutable global state and a heuristic that probe P1 resolved to `:elixir_uuid` (an unused dep) as the config domain, and a shipped surface carrying test backdoors, 8 unused deps, and a CLI whose Optimus spec is unreachable.

## Archetypes

Five recurring loss patterns. Fix the pattern, not the instance.

### AR-1 -- Success without effect

Write-shaped operations report success on paths where the effect did not happen. The failure is always logged, never returned. `Server.put/2` discards `write_config/1`'s result (`lib/config/server.ex:471`) whose failure branch returns `Logger.error/1`'s `:ok` (`server.ex:731-740`); state and cache then advance, so memory diverges from disk and *stays* divergent (P3: `get("k")` -> `{:ok, "v"}`, file absent). The same shape recurs in delete, env-overrides, cache fallbacks, and the enoent policy.

### AR-2 -- Two of everything

Every core concern has two implementations, one favoured, the other neither removed nor kept correct: nested get/put/write (Cfg vs Server, with a behavioural fork -- Cfg writes skip the watcher token so they self-notify as external), four not-found dialects, two CLI dispatch paths (the Optimus spec is dead), a facade missing `delete` and any location API (arca_cli hallucinated `get_config_location/0` -- it never existed in any commit), duplicated `ensure_*` helpers, two CI workflows, three version strings.

### AR-3 -- The notification system describes a different system

Three channels (per-key subscribers, 1-arity config callbacks, 0-arity callbacks) x five mutation paths (put, delete, reload, external detect, switch) with an incoherent, untested matrix (P5): per-key fires **only** on internal put/delete -- never for external changes, the case the watcher exists for; 1-arity fires **only** on external; 0-arity double-fires on the watcher path. The watcher itself hard-matches reload success (`file_watcher.ex:185`), so one malformed hand-edit crashes it into permanent dormancy, and its write-token suppresses *any* change in the 5s post-write window.

### AR-4 -- Location is ambient guesswork

Config location = f(app-specific env var, generic env var, app config, CWD-relative default, file-existence flip, domain heuristic), resolved fresh on every access, mutated globally at runtime by the library itself (`switch_config_location` writes env vars). README documents the precedence **backwards** -- the root cause of arca_cli A22. The domain heuristic scans started applications and resolved to `:elixir_uuid` in P1. This archetype is why every test is `async: false`, why tests write into the repo root and its parent, and why `.arca_config/` artifacts are committed to git.

### AR-5 -- Shipped scaffolding

Test and dev concerns living in the product: `{:reset_for_test, ...}` in Server (`server.ex:434-437`), `{:reset_to_dormant, ...}` in FileWatcher (`file_watcher.ex:160-164`), cache rescue-clauses commented "for tests" that cannot fire (exit != raise), 8 of 13 deps unreferenced, an escript CLI occupying the facade module, dead test-support code, committed debug scripts and backups.

## Findings ledger

Severity: C critical, H high, M medium, L low. Confidence: X executed, R read-confirmed (structural fact), T traced (wants red test).

### AR-1 -- Success without effect

| ID    | Sev | Conf | Finding                                                                                                                                        | Evidence                                                            | Prov  |
| ----- | --- | ---- | ---------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------- | ----- |
| AF-01 | C   | X    | `put/2` replies `{:ok, value}`, advances state + cache, when the disk write failed; memory serves phantom values thereafter                     | `server.ex:471,731-740`; probe P3b: `:eacces` logged, `{:ok, "v"}` returned, disk unchanged, `get` serves phantom | [O][X] |
| AF-02 | C   | R    | `delete/1` identical: write result discarded, replies `{:ok, :deleted}`                                                                         | `server.ex:498,513`                                                  | [O]   |
| AF-03 | M   | R    | `apply_env_overrides/0` discards each `put/2` result; failed override is silent                                                                 | `lib/arca_config.ex:196`                                             | [O]   |
| AF-04 | M   | R    | On-demand load failure in `handle_call({:get,...})` swallowed: marks `loaded: true`, every get thereafter reports "Key not found", never "load failed" | `server.ex:441-456`                                            | [O]   |
| AF-05 | M   | R    | Cache `rescue`-clauses fabricate success "for tests" and cannot fire for their stated purpose (dead-GenServer produces an exit, not an exception) | `cache.ex:56-64,73-81,93-101`                                       | [O]   |
| AF-06 | H   | R    | enoent conflated with empty config (`{:ok, %{}}`); switching to a nonexistent/typo'd path silently succeeds with empty config -- and later writes create it | `cfg.ex:148-151`; enshrined: `switch_location_test.exs:217-231` (comments narrate the drift) | [F]   |
| AF-07 | M   | R    | `Map.put` raise-path tested only via a meck that makes `Server.put` return an error the real one cannot produce; the real failure is untestable through the API | `map_test.exs:113-128` ("tricky to test" comment)                | [F]   |

### AR-2 -- Two of everything

| ID    | Sev | Conf | Finding                                                                                                                                          | Evidence                                                             | Prov     |
| ----- | --- | ---- | ------------------------------------------------------------------------------------------------------------------------------------------------ | -------------------------------------------------------------------- | -------- |
| AF-08 | H   | R    | Dual nested get/put/write: `Cfg.{get,put,update_nested_config,write_config}` vs `Server.{get_in_nested,put_in_nested,write_config}`; Cfg writes skip `FileWatcher.register_write/1` so they notify as external | `cfg.ex:388-525` vs `server.ex:635-740`; token only at `server.ex:716-717` | [O]      |
| AF-09 | H   | R    | Four not-found dialects: `:not_found`, `"Key not found"`, `"'#{key}' not found"`, `"No such property: ..."`; arca_cli text-matches the prose      | `cache.ex:38`, `server.ex:639,644`, `cfg.ex:399`, `cfg.ex:362`; consumer: `arca_cli lib/arca_cli.ex:1083-1098` | [O][H]   |
| AF-10 | H   | R    | Facade incomplete: `delete/1` absent (consumer reaches into Server, with apologetic comment), and no location-inspection API at all -- arca_cli calls `Arca.Config.get_config_location/0`, which has never existed in any commit (`git log -S` empty) | `server.ex:133-156` vs facade; `arca_cli test/test_helper.exs:80-83`, `cli_command_helper.ex:350` | [O][H][F] |
| AF-11 | M   | R    | CLI double dispatch: `main/1`'s `case` intercepts set/get/list/watch before Optimus; the ~55-line Optimus subcommand spec and 4 `process_command/1` clauses are unreachable | `arca_config.ex:490-510` vs `:526-569,573-587`                    | [O]      |
| AF-12 | L   | R    | `ensure_directory_exists/1` + `ensure_file_exists/2` duplicated verbatim                                                                          | `file_watcher.ex:235-254` vs `init_helper.ex:80-99`                  | [F]      |
| AF-13 | M   | R    | `Access.pop/2` and `get_and_update/3`'s `:pop` never pop; comment claims "we can't really delete keys" while `Server.delete/1` exists; a test enshrines the no-op | `map.ex:139-156`; `map_test.exs:174-180`                        | [O]      |
| AF-14 | L   | R    | Two CI workflows (ci.yml + test.yml) both run the full suite per push/PR; overlapping cell (1.18.4/OTP 28) runs twice; matrix caps at 1.18.4/OTP 28 while dev runs 1.20.2/OTP 29 | `.github/workflows/{ci,test}.yml`                    | [F]      |
| AF-15 | L   | R    | Version triple-dialect: mix.exs `0.2.0`, config.exs `"0.1.0"`, README both `~> 0.1.0` and `~> 0.2.0`. Plus two inert declared keys: `mix_tasks:` (not a Mix.Project option) and `ansi_enabled: true` inside `def application` (not an OTP application key -- silently ignored, no warning). arca_cli removed the identical `ansi_enabled` line in 0.5.0 as its C10: same author, same junk key, two repos | `mix.exs:5,13-16,26`, `config/config.exs`, `README.md:13,27` | [O][F][vc lead, verified] |
| AF-16 | M   | R    | Dead `{:ok, conf}` clause in `notify_external_change/0` (`:get_config` replies a bare map; no catch-all so a non-map would CaseClauseError) -- and a test mocks **GenServer itself** to force the dead clause to run, enshrining it | `server.ex:357-361,429-431`; `server_test.exs:341-375` | [O][F]   |

### AR-3 -- The notification system describes a different system

| ID    | Sev | Conf | Finding                                                                                                                                            | Evidence                                                          | Prov   |
| ----- | --- | ---- | --------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------- | ------ |
| AF-17 | H   | X    | Channel x path matrix incoherent: per-key never fires on external/reload/switch (subscribe doc promises unqualified delivery); 1-arity never fires on put/delete/reload; 0-arity fires twice per watcher-detected change | probe P5; `server.ex:476-483,517-533,579`; `file_watcher.ex:184-186`; doc `arca_config.ex:293-311` | [F][X] |
| AF-18 | H   | T    | Watcher hard-matches `{:ok, _} = Server.reload()`; malformed JSON -> MatchError -> restart into `watching: false` with no timer: permanent silent dormancy after one bad hand-edit | `file_watcher.ex:185`, `cfg.ex:161-163`, `file_watcher.ex:105-109`; zero test exposure (reload is meck'd in `file_watcher_test.exs:111`) | [O]    |
| AF-19 | M   | R    | Write-token suppresses **any** change while set (external edits in the 5s window are dropped and `last_info` advances past them); the token's value is never compared, only nil-ness -- the "unique token" contract is decorative; the suppress-everything semantics are enshrined by test | `file_watcher.ex:166-213`; `file_watcher_test.exs:73-104` | [O]    |
| AF-20 | H   | X    | Ancestor cache entries stale after nested put: leaf-only `Cache.put`; `get("db")` served the pre-put map while disk had the new value               | `server.ex:474,746-763`; probe P2                                  | [O][X] |
| AF-21 | L   | R    | Notification deferred behind the reply (`Process.send(self(), ...)` after replying); put-then-expect-message races; undocumented                    | `server.ex:480`                                                    | [O]    |
| AF-22 | L   | R    | `stop_watching` resurrectable: an in-flight `:check_file` re-schedules the timer while dormant; `start_watching/1`'s config_file param is honoured only until the first tick re-derives from Cfg | `file_watcher.ex:203-212,175,196-199`                | [F]    |

### AR-4 -- Location is ambient guesswork

| ID    | Sev | Conf | Finding                                                                                                                                              | Evidence                                                              | Prov     |
| ----- | --- | ---- | ----------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------- | -------- |
| AF-23 | C   | R    | README documents env-var precedence **backwards** ("generic ... highest priority"); code resolves app-specific first. This inversion is the root cause of arca_cli A22 (their env isolation silently inert across nine files) | `README.md:117-125` vs `cfg.ex:235-252`; consumer workaround `arca_cli test/test_helper.exs:103-110` | [F][H] |
| AF-24 | M   | R    | README's location story false: promises `~/.my_app` then `./.my_app`; both defaults are the same CWD-relative `.app_name/` (docstring admits "within the current working directory"). README also sells `config/.env` auto-loading as a library feature; it is this repo's own config script, never evaluated in consumers | `README.md:106-113,142-165` vs `cfg.ex:530-555`, `config/dotenv.exs` | [F]      |
| AF-25 | H   | X    | `config_file/0` resolution flips on file existence (home-if-exists else local): the answer changes when files appear. Executed: with the configured file absent, a `put` was redirected to the CWD default and wrote `.arca_config/ro.json` into the repo root -- a location the caller never configured | `cfg.ex:197-215`; probe P3 (first run) | [F][X]   |
| AF-26 | H   | X    | Domain detection heuristic ($callers dictionary walk + first non-system app in `started_applications()` order) is nondeterministic; probe resolved the domain to `:elixir_uuid` -- an unused dependency -- steering env prefix and default path | `cfg.ex:37-95`; probe P1                        | [F][X]   |
| AF-27 | M   | R    | The library's location mechanism is global mutation: `switch_config_location` writes/deletes env vars (`server.ex:552-565`), InitHelper writes env vars (`init_helper.ex:65-66`), tests and doctests do the same. Forces `async: false` on all 9 test files; collided with arca_cli's own env expectations | `server.ex:536-603`, `init_helper.ex:57-76`; all test setups | [O][F] |
| AF-28 | M   | R    | Trailing-slash "exact string preservation" wart: env-derived paths deliberately not expanded so a test asserting string identity passes; `local_config_pathname/0` always expands (asymmetric); the enshrined test also leaks `/tmp/` + `bozo.json` into the env | `cfg.ex:244-252` vs `:282`; `cfg_test.exs:99-109`  | [F]      |
| AF-29 | M   | R    | Facade doctests set `ARCA_CONFIG_PATH`/`FILE` and never delete them (Cfg doctests do clean up); `doctest Arca.Config` runs in **two** files, doubling the pollution | `arca_config.ex:42-47,213-218` etc; `cfg_test.exs:49`, `callback_test.exs:3` | [F] |
| AF-30 | M   | R    | Env restore-by-superset: `System.put_env(previous_env)` cannot delete vars added during the test; suite passes only because every downstream file jams its own vars | `cfg_test.exs:55,77-80`                                  | [F]      |
| AF-31 | M   | R    | Tests write into the repo root (`.arca_config/` created by `setup_all`, file removed but dir kept) and clean up `.test_app` in HOME, CWD, **and the repo's parent dir** -- an admission the suite escapes its sandbox; 4 `.arca_config/*` artifacts are committed to git, including a 2024 OAuth config | `cfg_test.exs:22-36`, `test_helper.exs:2-16`, `git ls-files .arca_config/` | [F] |

### AR-5 -- Shipped scaffolding

| ID    | Sev | Conf | Finding                                                                                                                                     | Evidence                                                              | Prov   |
| ----- | --- | ---- | -------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------- | ------ |
| AF-32 | M   | R    | 8 of 13 deps unreferenced **inside arca_config** (`ok`, `owl`, `ucwidth`, `pathex`, `table_rex`, `elixir_uuid`, `castore`, `dotenv`; `certifi` also); all direct declarations. `dotenv` unused even where declared -- `config/dotenv.exs` hand-parses `.env`. `optimus` (2 refs) reachable only via the half-dead CLI. **In-repo silence is NOT grounds for removal here** -- see the ruling and downstream evidence below. Softened from handover: arca_cli pins the same optimus fork itself | `mix.exs:30-47`, grep table, `mix deps.tree`; downstream evidence in the dependency section below | [O][H][F] |
| AF-40 | H   | R    | `config/.env` (present on disk, gitignored) is applied by `System.put_env/2` during **config evaluation** (`config/dotenv.exs`, imported at `config/config.exs:6` for dev/test), unconditionally overwriting anything the shell exported. It sets `ARCA_CONFIG_CONFIG_PATH=.arca_config` and `ARCA_CONFIG_CONFIG_FILE=config.json`, so any attempt to redirect this repo's own test config via the documented env vars is silently overridden before a single test runs. This is the mechanism behind AF-31 (tests writing into the repo root) and the same defect class as arca_cli's A22. A fresh clone has no `config/.env`, so the resolution path differs between machines even where the answer coincides | `config/.env:2-3`, `config/dotenv.exs`, `config/config.exs:6`; `.gitignore:55` | [vc lead, verified] |
| AF-33 | M   | R    | Test backdoors in production surface: `{:reset_for_test, ...}` (Server), `{:reset_to_dormant, ...}` (FileWatcher, used by phase_based_test)   | `server.ex:434-437`, `file_watcher.ex:160-164`, `phase_based_test.exs:23,33` | [O] |
| AF-34 | M   | R    | Facade module is Application callback + API facade + entire escript CLI (Optimus spec, handlers, `watch_loop/1`, `try_convert_value/1`): 690 lines, Thin Coordinator violation | `arca_config.ex` throughout                             | [O]    |
| AF-35 | L   | R    | Repo cruft: `AGENTS.md.bak`, `.backup/` (8 entries), `scripts/{reproduce_path_bug,simulate_dependent_project,simulate_problematic_setup}.exs`, committed `.arca_config/` artifacts | root listing; `git ls-files`                  | [O][F] |
| AF-36 | L   | R    | Dead test-support: `write_default_config_file/2` has zero callers, and its cleanup registers into `Process.put(:on_exit, ...)` which nothing ever executes | `config_test_support.ex:9-54`; caller grep empty         | [F]    |
| AF-37 | M   | R    | `Cfg` aliased `LegacyCfg` yet is the live loader on every load/reload/switch path and a documented public API with doctests; ownership ambiguous, "is it dead?" unanswerable without a ruling | `server.ex:16`; call sites throughout           | [O]    |
| AF-38 | M   | R    | Test theatre: 2 of 4 auto_config tests hand-write the expected output to disk then assert the file contains it (comments admit bypassing `apply_env_overrides` for "timing issues"); the override mechanism has exactly one real test; plus one `:timer.sleep(100)` | `auto_config_test.exs:48-88,145-196,181`; real test `phase_based_test.exs:108-140` | [F] |
| AF-39 | L   | R    | `usage-rules.md` -- the file consumer LLM sessions read as library guidance -- is Intent project scaffolding with an empty "Project conventions" placeholder; zero consumer API content | `usage-rules.md:8-16`                            | [F]    |

### Cross-cutting facts (not defects, load-bearing for remediation)

| Fact                                                                                                    | Evidence                                             |
| ------------------------------------------------------------------------------------------------------- | ---------------------------------------------------- |
| arca_cli is the only consumer in the fleet; sibling probes clean (no refs, no `function_exported?` traps beyond arca_cli's) | greps over arca_id/dbutils/notionex/doc/optimus      |
| The deletion tripwire: arca_cli probes `register_change_callback/2` existence as a liveness proxy        | `arca_cli lib/arca_cli.ex:118-130`                   |
| arca_cli pinned `8b30615`; drift to HEAD is mix.lock-only (`git diff 8b30615..HEAD -- lib/ mix.exs` empty) | git                                                |
| Env-override key mapping collapses `_` to `.`: `..._OVERRIDE_LLM_CLIENT_TYPE` -> `llm.client.type`, underscored top-level keys unreachable (probe P7) | `arca_config.ex:186-190`; probe P7 | 

## Dependencies: the ruling, my own error, and the downstream evidence

vc reported the eight-unused-deps finding independently (cc/inbox.vc.md, 16:05) and **hv overruled it** (retracted 16:13). The ruling, which vc restated and which applies to this audit with equal force:

> A dependency or public function that this repo does not call but downstream does is not dead surface -- it is *untested contract surface*, which is the more dangerous thing, because nothing here will tell you when you break it. The remedy is to write tests that pin the intended usage, not to delete.

**AF-32 as originally drafted, and AC-05.1 as originally written, made the same invalid inference vc was overruled for**: in-repo silence treated as grounds for removal. arca_config is a library; a grep inside it cannot see a single consumer. The finding of fact (zero internal references) stands; the implication (removable) did not, and has been withdrawn. This correction is mine, not something hv had to catch on the contract -- ratification covered the contract's scope, not this inference buried inside one AC.

Repaired standard, now written into AC-05.1: **default is KEEP; removal requires positive downstream evidence, and the WP-06 arca_cli rebuild is the proof, not the grep.**

Downstream evidence gathered 2026-08-04 (this is better than an in-repo grep, and still not proof -- it sees the local fleet only):

| Dep                            | Fleet usage                                                        | Reads as                                                   |
| ------------------------------ | ------------------------------------------------------------------- | ---------------------------------------------------------- |
| `ok`                           | arca_cli 3 hits, all non-library: a dead-code **gate test asserting `OK.Pipe` is imported nowhere**, plus the string `"OK"` in renderer test data. arca_cli does not declare `:ok` | not load-bearing; arca_cli actively gates against it        |
| `owl`                          | arca_cli 57 hits, **and arca_cli declares `{:owl, "~> 0.12"}` itself** | not load-bearing transitively; consumer is self-sufficient  |
| `table_rex`, `elixir_uuid`     | hits only in arca_notionex, which **does not depend on arca_config**; it declares `table_rex` itself, and its `UUID` hits are prose in comments | not load-bearing; no dependency path exists                 |
| `ucwidth`, `pathex`, `castore`, `certifi` | zero hits anywhere in the fleet                          | no fleet evidence either way                                |

Fleet scope, verified: **arca_cli is the only repo in the fleet that depends on arca_config** (`arca_id`, `arca_dbutils`, `arca_notionex`, `arca_doc`, `arca_optimus` all declare zero). External consumers outside this fleet cannot be enumerated from here; arca_config is a git dep, not published to Hex, which bounds but does not eliminate that risk.

So the fleet evidence happens to support removal for all eight. It does not license removal on its own, and WP-05 does not act on it alone -- AC-05.1 requires the WP-06 rebuild to carry each removal.

The inverse scope item hv named ("identify what downstream relies on arca_config for, and give it coverage here so the contract is enforced rather than assumed") is a genuine addition to a ratified contract, proposed as **AC-00.4** and flagged to hv rather than slipped in.

## Work packages (risk-ordered)

| WP    | Archetype | Scope                                                                                                                       | Principal findings                          |
| ----- | --------- | --------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------- |
| WP-01 | AR-1      | Truthful returns: persistence failures surface as errors; state/cache never advance past a failed write; enoent semantics ruled | AF-01..07                                   |
| WP-02 | AR-2      | One lookup path, one error dialect, complete facade (delete, location API); Access honesty; dead clause + dead CLI dispatch | AF-08..13, AF-16, AF-37                     |
| WP-03 | AR-3      | Notification matrix ratified + implemented; watcher survives malformed JSON; token window fixed; cache coherence on put     | AF-17..22, AF-20                            |
| WP-04 | AR-4      | Location model: precedence ruled + documented once; deterministic domain; README rewrite; suite isolation (no repo-root writes, exact env restore) | AF-23..31                 |
| WP-05 | AR-5      | Surface + dependency pruning: deps to used set, CLI ruling executed, test backdoors out, facade thinned, cruft removed, one CI | AF-32..36, AF-38, AF-39, AF-11, AF-12, AF-14, AF-15 |
| WP-06 | --        | Downstream verification + release: vc rebuilds arca_cli, 710 tests; migration notes; CHANGELOG; semver + tag (hv)           | cross-cutting                               |

## Rulings (hv, 2026-08-04)

Contract ratified. Six of seven rulings decided as proposed; R3 remains open and blocks only WP-05 scope.

| #  | Ruling                                                                    | Blocks | Decision                                                                                                              |
| -- | -------------------------------------------------------------------------- | ------ | ---------------------------------------------------------------------------------------------------------------------- |
| R1 | Canonical error shape for the unified dialect                              | WP-02  | DECIDED in shape: `{:error, {:config, reason_atom, key_path}}`. Final wire format pending vc concurrence -- arca_cli text-matches today's prose (`arca_cli.ex:1083-1098`) and must move to matching the atom. Asked in `handover-to-vc.md`. |
| R2 | Precedence direction                                                       | WP-04  | DECIDED: keep the code (app-specific > generic) -- arca_cli now depends on it -- and fix the README. The README is the defect, not the resolver. |
| R3 | Escript CLI: extract-and-fix vs delete                                     | WP-05  | **OPEN.** The only ruling still needed. Extract keeps `optimus` (and the escript/mix-task surface); delete removes `optimus` plus the last non-Jason runtime dep and shrinks AC-05.1/AC-05.3 to a removal. Audit leans delete: the Optimus spec is already unreachable (AF-11), the CLI is undocumented beyond README's `./scripts/cli`, and no consumer in the fleet invokes it. Not needed until WP-05. |
| R4 | enoent semantics                                                           | WP-01  | DECIDED as proposed: `{:ok, %{}}` survives only for the documented first-run bootstrap path; `switch_config_location/1` to a nonexistent path fails and leaves the previous location live. |
| R5 | Semver for the breaking release                                            | WP-06  | DECIDED: 0.3.0 -- stay in 0.x until the location model (AR-4) settles.                                                |
| R6 | CI target matrix + single workflow                                         | WP-05  | DECIDED: one workflow; floor Elixir 1.18, add a 1.20 / OTP 29 cell to match the dev toolchain.                        |
| R7 | `Access` behaviour on the Map facade                                       | WP-02  | DECIDED: implement `pop` honestly via `Server.delete/1` rather than dropping the behaviour.                           |

## Changed-tests discipline

Tests that assert a defect are changed with the fix and each change is flagged in `impl.md`'s changed-tests ledger for vc. Known-in-advance: `switch_location_test.exs:217-231` (silent success on nonexistent path), `map_test.exs:174-180` (pop no-op), `server_test.exs:341-375` (GenServer meck reaching dead clause), `file_watcher_test.exs:73-104` (suppress-everything token), `cfg_test.exs:99-109` (trailing-slash string identity), auto_config theatre tests.

## Recall record (sealed pre-read vs Fable pass)

Sealed set: 23 findings. Fable pass confirmed 21, executed 4 of them (AF-01, AF-20, env-override collapse, matrix fragments), softened 2 (Elixir-version claim -- `~> 1.18` is compatible with dev's 1.20.2, the real defect is the stale CI matrix + version triple-dialect; optimus-override blast -- arca_cli pins the fork itself). Fable-new findings not in the sealed set: AF-06, AF-12, AF-14, AF-16 (test half), AF-23, AF-24, AF-25, AF-26, AF-28, AF-29, AF-30, AF-31, AF-36, AF-38, AF-39, the full AF-17 matrix, and the P1/P3 executions. The independence of this comparison is limited by the shared context (see provenance); the direction "Fable found things Opus missed" survives, the reverse probe does not.
