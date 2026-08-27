---
verblock: "04 Aug 2026:v1.0: matts - ST0002 release verification package for vc"
st_id: ST0002
title: "arca_config 0.3.0 -- release verification package for vc"
---

# arca_config 0.3.0 -- release verification package

For the validation node. Self-contained: every claim carries a `file:line` or a command you can run. Written 2026-08-04 against arca_config `03969fa`. The analysis-phase handover is `handover-to-vc.md` and is now historical -- this supersedes it for anything to do with the release.

## What you are being handed

**Five of six work packages are DONE and pushed.** ST0002 took arca_config from 128 tests to 222, closed 40 audit findings across 5 archetypes, and closed a further 21 from a critic pass hv authorised at the end.

| | |
| --- | --- |
| Commit | `03969fa` on `main`, GitHub `matthewsinclair/arca_config` |
| Version | 0.3.0 (ruling R5). **Untagged** -- the `v0.3.0` tag is hv's, per AC-06.3 |
| CI | Green on 1.18.0/OTP 27, 1.18.4/OTP 28, 1.20.2/OTP 29 (run 30944489673) |
| Suite | 222 passed (48 doctests, 174 tests), 8 seeds, zero stray output |
| Coverage | 90.47%, threshold 90 enforced |
| Contract | 34/38. The 4 open are yours and hv's |

## To pick it up

```bash
cd arca_cli
mix deps.update arca_config
```

Your lock pins `8b30615`, so you have seen none of this. You depend on it as `{:arca_config, github: "matthewsinclair/arca-config", branch: "main"}` (`arca_cli/mix.exs:33`) -- a branch dep, so there is no tag to wait for. GitHub redirects the `arca-config` spelling to `arca_config`; same repository, verified.

## One test of yours WILL fail, by design

`test/arca_cli/error_format_test.exs`, "failure: a setting that does not exist", asserts:

```
"error: settings.get: setting not found: nosuchkey"
```

Ruling R1 unified the error dialect. `Arca.Cli.setting_error/2` (`arca_cli.ex:1080-1092`) classifies a missing setting with three clauses -- a bare `:not_found` atom, a binary containing "not found", and a generic fallback. The canonical shape matches **neither accepting clause**, so it renders through the fallback as `cannot read setting nosuchkey: {:config, :not_found, ["nosuchkey"]}`.

**Degraded message text on an error path. Never a crash. Every `{:ok, _}` path is untouched.** The clause you need, placed **above** the `is_binary` clause:

```elixir
defp setting_error(id_str, {:config, :not_found, _key_path}), do: "setting not found: #{id_str}"
```

I have not written it. arca_cli is yours.

## The error dialect, in full

Every public failure is now `{:error, {:config, reason, detail}}`. `reason` is a machine-matchable atom that will not be reworded; `detail` is the key path for key-scoped failures and the underlying cause otherwise.

| Before | After |
| --- | --- |
| `{:error, "Key not found"}` | `{:error, {:config, :not_found, ["database", "host"]}}` |
| `{:error, "'database.host' not found"}` | same as above |
| `{:error, "No such property: \"id\""}` | `{:error, {:config, :not_found, ["id"]}}` |
| `{:error, "Failed to load config file: enoent"}` | `{:error, {:config, :load_failed, :enoent}}` |
| `{:error, :eacces}` | `{:error, {:config, :write_failed, :eacces}}` |

Nothing was thrown away: the prose that used to *be* the error is now the `detail`, so a parse failure still reports its position and token. `Arca.Config.Error.message/1` renders any reason for a person, and is total by construction.

**Deliberately unchanged, and I want you to push on both.** `Arca.Config.Cache` keeps `{:error, :not_found}` / `{:error, :cache_unavailable}` -- its "not found" means *not cached*, and `Server.normal_get/1` is precisely the code that must tell a cold cache from a missing key. `Server.remove_callback/1` keeps `{:error, :not_found}` -- a callback reference is not a config key. Both documented in `Arca.Config.Error`'s moduledoc. If either reads as a rationalisation, say so.

## Behaviour changes, ranked by risk to arca_cli

1. **`Cfg.get/1` reads server state, not the file.** It used to re-read on every call, so setting location environment variables behind the running server redirected reads. It now delegates to `Server`. Use `switch_config_location/1` or `reload/0`. **Six seeds missed this locally; one different ordering caught it instantly.** If arca_cli's isolation sets paths and then reads, check it -- this is the change most likely to bite you.
2. **Writes can fail.** `put/2`, `delete/1`, `put!/2`, `delete!/1` reach disk. A `put` against a read-only file used to log `:eacces`, return `{:ok, value}`, and serve the phantom from memory forever.
3. **`delete/1` on a key that was never set is an error**, not `{:ok, :deleted}`.
4. **A `put` against an unparseable config file is refused**, not repaired. It used to silently discard the file and replace it.
5. **`switch_config_location/1` to a location with no config file errors** and leaves the previous location fully live (ruling R4).
6. **The config domain is never guessed.** `config_domain/0` is application config or `:arca_config`. arca_cli sets its own, so this should be inert for you -- confirm.
7. **`config_file/0` no longer falls back** to a working-directory default when the configured file is missing.
8. **Domain-specific env vars outrank generic ones**, and always did -- the README said the opposite, which is the root cause of your A22.
9. **The escript target is gone.** `mix arca.config` replaces it (ruling R3: extract, not delete).

All of this is in `CHANGELOG.md`, written for exactly this.

## What we need from you (the whole remaining contract)

- **AC-00.2** -- rebuild arca_cli against `03969fa` and run its full suite. Failures triaged to migration notes or fixed here.
- **AC-06.1** -- your report on that rebuild, cited in `impl.md`.
- **AC-00.1** -- your ack on the public-symbol removal log (`impl.md`). **No public symbol was retired in the entire thread.** Every deletion is a private function, an unreachable clause, or a repository file. The two families that looked deletable -- `Cfg.get/put` and `Arca.Config.main/1` -- are delegates instead.
- AC-06.3 is hv's tag.

## Where to attack, in the order I would

**1. The critic pass found four criticals the Fable audit missed, one of which was data loss.** That is the most important fact in this document. `read_current_config/1` folded every read and decode failure into memory and ran *immediately before overwriting the file*, so a config hand-edited into invalid JSON was silently discarded. Archetype AR-1 in the write path, in the one place WP-01 did not look. **A thorough audit still had holes; assume this document does too.**

**2. Three of the critic's findings were this thread's own lessons surviving in the tests** -- a `try/rescue` around `Registry.start_link` three lines above the correct helper, `:sys.replace_state` fabricating server state (AC-05.2's backdoor moved from `lib/` to `test/`), and AF-38's theatre tests still asserting on JSON they had just written. **Worth the same sweep of arca_cli's suite**: if a defect class was worth removing from `lib/`, grep for it in `test/`.

**3. A mock hid a real bug for an hour.** AC-02.2 shipped a `Protocol.UndefinedError` on every error path -- five sites interpolated a tuple reason into a string. The suite stayed green because nothing exercised a CLI error path, and the one `Map` failure test mocked `Server.put` to return a *binary* reason, so it passed through the exact contract change it existed to cover. **Any arca_cli test that mocks arca_config is now suspect for the same reason.**

**4. Coverage was never enforced.** The old workflow ran `mix test --cover || true`. Removing the `|| true` surfaced a threshold that had never been met, and the real gap was `Mix.Tasks.Arca.Config` at **0%** -- the CLI path ruling R3 kept *because* it is the documented one. Check whether arca_cli has the same shape of unenforced gate.

**5. Fifteen tests changed shape** and every one is in `impl.md`'s changed-tests ledger with before/after. Two categories: tests that asserted a defect (changed with the fix), and tests whose assertions moved from grepping prose to matching data. None were weakened to pass; where a test was the only written record of a contract, the implementation was narrowed instead -- twice.

## Reading order

| File | What it is |
| --- | --- |
| `CHANGELOG.md` | The migration notes. Start here |
| `usage-rules.md` | Consumer DO/NEVER contract -- what your LLM session reads at `deps/arca_config/usage-rules.md` |
| `intent/st/ST0002/impl.md` | As-built per WP, changed-tests ledger (15 rows), public-symbol removal log |
| `intent/st/ST0002/acceptance.md` | The 38-AC contract with live AT status |
| `intent/st/ST0002/design.md` | 40-finding ledger, 5 archetypes, all 7 rulings, the ratified notification matrix |
| `test/config/consumer_contract_test.exs` | Every call arca_cli makes, each citing the arca_cli `file:line`. **If it is missing one of your calls, that gap is the thing it exists to prevent** |

## Coverage of this document

What I checked: everything in `lib/` and `test/` in this repository, CI, the fleet probe across five sibling repos, and arca_cli's call sites by reading its source.

What I did **not** check: I have not run arca_cli's suite -- that is AC-00.2 and it is yours. I have not verified the runtime behaviour of any arca_cli code path. The critic pass executed nothing; it read code. And one correction already on the record: the analysis handover claimed arca_cli hard-matches `get_config_location/0` at `cli_command_helper.ex:350` -- **that is inside a `@doc` heredoc and never raised**. It is implemented now regardless (AC-02.3), but correct your notes.
