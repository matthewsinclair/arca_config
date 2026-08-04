---
node: cc
name: Control Claude
role: control
session_id: 797c6bb0-eb52-4b00-9870-3095616dfef2
heartbeat_at: 2026-08-04T21:12Z
status: active
focus: "ST0002 CLOSED 38/38 by vc. No claims, nothing in flight. Awake and holding for hv"
claims: []
---

# Control Claude (cc)

## Roster

| Node | Who                         | Where it runs                                                                                                                           |
| ---- | --------------------------- | --------------------------------------------------------------------------------------------------------------------------------------- |
| hv   | Matthew Sinclair            | human; adjudicates scope, holds model switches + release                                                                                |
| cc   | this session                | `arca_config`, node dir `intent/whiteboard/cc/`                                                                                         |
| vc   | session 7a8b32c5, validator | node dir `intent/whiteboard/vc/` **in this repo** -- one session validates both arca_config and arca_cli, same session_id on both boards |

**Read `inbox.vc.md` at every fold, not only at pickup.** Three vc entries once sat unread for a whole session because the node did not exist when pickup ran. Four entries live (19:25--20:40), all handled during the session, none cleared.

## DOING

Nothing, and nothing is claimed. **ST0002 closed 38/38 by vc at `deff38f`**, moved to `intent/st/COMPLETED/ST0002/`. Awake and holding for hv.

## TODO -- open, but none of it is arca_config's

- **Three commits sit unpushed** (`df0e700`, `0aa3509`, `deff38f` -- vc's close-out). Both `local` and `upstream` are 3 behind. `v0.3.0` itself is pushed and unaffected. hv's call whether these go up.
- **vc's MED fast-follow lands in arca_cli, not here**: `Arca.Cli.load_settings/0` maps `{:config, :load_failed, :enoent}` to `{:ok, %{}}` unconditionally, so a mistyped `ARCA_CLI_CONFIG_PATH` reports an empty config rather than a wrong path. **The arca_config side of the fix already exists** -- `Cfg.config_location/0` returns `source: %{path:, file:}` (`cfg.ex:305-316`), built as AC-02.3 for exactly this. Nothing to build here unless the fix needs more than `source` carries.
- **vc names one unstarted piece**: sweeping arca_cli's suite for the three lessons this thread's tests encode. arca_cli, not here.
- The path that would reopen work in this repo -- vc's rebuild surfacing failures -- **did not fire**. arca_cli is 782 green across six seeds against `5db55a4`.

## State at fold

| | |
| --- | --- |
| Tag | **`v0.3.0`**, annotated, pushed. The first tag this repo has ever had |
| Commit | `deff38f` on `main`, **3 ahead of both remotes**; the tag points at `ccd8fb5`, whose tree is identical to the CI-green build `03969fa` (everything between is documentation) |
| Contract | **38/38 PASS**; ST0002 DONE, in `intent/st/COMPLETED/` |
| WPs | WP-01..WP-05 DONE -- gates 6/6, 5/5, 6/6, 7/7, 6/6. WP-06 closed by vc |
| Suite | arca_config 222 passed (48 doctests, 174 tests), 8 seeds, zero stray output. arca_cli **782 passed** against `5db55a4`, six seeds (vc) |
| Gates | compile `--warnings-as-errors` clean, `mix test --warnings-as-errors` clean, format clean, coverage 90.47% vs threshold 90 |
| CI | green on 1.18.0/OTP 27, 1.18.4/OTP 28, 1.20.2/OTP 29 |

## Watch-outs

- **Do not delete `register_change_callback/2`.** Zero callers here *and* zero in arca_cli -- `arca_cli.ex:129` only asks whether it exists. Delete it and every `save_settings` downstream silently stops persisting. Now pinned by `consumer_contract_test.exs`, so the suite fails instead.
- **`Cfg.get/1` reads server state, not the file.** Moving the location behind the running server no longer redirects reads: use `switch_config_location/1` or `reload/0`. Six seeds missed this; one different ordering caught it at once.
- **`Arca.Config.Cfg` is the location and load authority**, not legacy. The `LegacyCfg` alias is gone (AF-37 resolved). Its `get/put` delegate to `Server`.
- **A seed sweep proves order-independence, not isolation, and not even order-independence reliably.** Twice this thread a multi-seed sweep certified something a single different ordering broke minutes later.
- **`mix compile --warnings-as-errors` cannot see test files.** Use `mix test --warnings-as-errors`; CI now does.
- **`test_helper.exs` fails the run** if the suite changes the working tree, the config env vars or `:arca_config`'s application settings. Do not silence it by widening the baseline.
- Anything public in a library with no in-repo callers is **untested contract surface, not dead surface**. No public symbol was retired in this entire thread.

## Decisions still live

- (2026-08-04) Claimed ST0002 as cc, confirmed by hv. Breaking changes permitted; the current API need not be preserved.
- (2026-08-04) All seven rulings decided and executed. R1 shape by hv with the wire format delegated to cc; R2 keep-code-fix-README; R3 extract; R4 enoent bootstrap-only; R5 0.3.0; R6 one workflow + a 1.20/OTP 29 cell; R7 implement `Access.pop` honestly. hv also ratified the notification matrix and accepted AC-00.4.
- (2026-08-04) hv standing rule: suite output is dots only. Now structural via `ExUnit.start(capture_log: true)` rather than a habit, after I leaked log lines twice.
- (2026-08-04) Tests that assert a defect get changed, not preserved, and every change is ledgered in `impl.md` for vc -- 15 rows. Where a test was the only written record of a contract, the implementation was narrowed instead. That happened twice.
- (2026-08-04) AC-06.3 says "tag by hv"; hv instructed me to make it rather than making it themselves. Tagged `ccd8fb5` rather than `03969fa` after diffing `lib`, `test`, `mix.exs`, `mix.lock` and `.github` to confirm the trees are identical -- a tag should mark the code CI verified.
- (2026-08-04) **The audit was thorough and still had holes.** The critic pass hv authorised found 4 criticals it missed, one of them data loss on the write path, plus a bug I had shipped an hour earlier. Assume the same of anything else written here.

## History

Full session record in `.history/20260804/` -- three parts (analysis, WP-01/03/04, WP-02/05 + release), plus the settled decisions retired from this board and the cleared vc inbox.
