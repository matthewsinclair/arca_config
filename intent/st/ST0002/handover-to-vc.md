# Handover: arca_config cc -> arca_cli vc (ST0002 analysis phase)

For the arca_cli session acting as verification node. This travels on its own: every claim carries `file:line` or a reproducible command, and nothing depends on the arca_config session's context. Written 2026-08-04 against arca_config HEAD `9925115`.

Reply via hv. Protocol 3.0 inboxes do not cross project boundaries.

## What is being handed to you

The ST0002 analysis phase, complete and ratified. No remediation has started; no `lib/` or `test/` file has been modified. What exists is a 39-finding ledger, a 36-AC contract, and 6 work packages.

Read in this order:

| File                                       | What it is                                                                       |
| ------------------------------------------ | -------------------------------------------------------------------------------- |
| `intent/st/ST0002/design.md`               | Method + provenance, 5 archetypes, 39-finding ledger, rulings, recall record     |
| `intent/st/ST0002/acceptance.md`           | The ratified contract: 36 ACs, red-first ATs, coverage map                       |
| `intent/st/ST0002/probes/probe_output.md`  | Verbatim execution output backing the 6 executed findings                        |
| `intent/st/ST0002/probes/*.exs`            | The probe scripts themselves -- re-runnable with `mix run`                        |
| `intent/st/ST0002/preread-sealed.md`       | The Opus pre-read, preserved for the provenance audit below                      |

## Provenance -- the thing you should be most sceptical about

The handover you wrote specified a **cold** Fable audit, and warned that supplying archetypes in advance turns discovery into confirmation. That property was **not** achieved, and the reason is on the record in `design.md`.

Sequence: this session read all 9 lib modules on Opus before your note arrived. When your note established that analysis belonged to Fable, the findings were sealed to a file rather than briefed. hv then switched the model **inside the same session**, so the sealed set was in the Fable context window. There was no cold audit available after that point.

What was run instead: verification-plus-extension. Every sealed claim was re-derived from source or executed rather than echoed; deliberate coverage was given to everything the pre-read had not touched (all 9 test files, `test_helper.exs`, `test/support/`, README, usage-rules, both CI workflows, `config/`, git history, sibling repos). Outcome: of 23 sealed findings, 21 confirmed (4 of them executed), 2 softened; 16 findings are Fable-new, concentrated in the unread territory.

The claim "Fable independently rediscovered these" is **not** supported and is not made anywhere in the docs. The claim "the evidence survives execution, and the unread territory was covered" is what the artifacts support. Judge the ledger on its evidence, not on its discovery story. If you want an independent check of the clustering specifically, that needs a fresh session with no access to `preread-sealed.md`, and it is worth saying plainly that no such check has happened.

## Corrections to your handover note (both verified here, commands included)

**1. `Arca.Config.get_config_location/0` has never existed.**

```
git log -S "get_config_location" --all     # empty
git grep -n "get_config_location" 8b30615  # not found at your pinned commit
git grep -n "get_config_location" HEAD     # not found at HEAD
```

Your `lib/arca_cli/testing/cli_command_helper.ex:350` hard-matches `{:ok, config} = Arca.Config.get_config_location()`. That is a latent `UndefinedFunctionError` on a path that evidently never executes -- your own lesson about green suites not proving reachability, pointing back at your repo. It is yours to fix, not ours to preserve. We are nonetheless **adding** the function (AC-02.3), because the facade genuinely lacks any location-inspection API; your call whether to keep the call site or drop it.

**2. The "two commits of unaudited drift" is mix.lock only.**

```
git diff --stat 8b30615..HEAD -- lib/ mix.exs   # empty
```

`aa926d0` is an Intent tooling upgrade (`.claude/`, `AGENTS.md`, `intent/`), `9925115` touches `mix.lock`. arca_cli's 710 green tests ran against source-identical arca_config. The drift risk is dependency resolution, not behaviour.

**3. The dep finding: you were retracted, and so was I.** Your original note flagged seven suspicious deps as its highest-signal lead. I confirmed the count as eight-of-thirteen unreferenced inside arca_config and wrote a contract AC that reduced deps "to the referenced set". That AC made **exactly the inference hv overruled you for** -- in-repo silence treated as grounds for removal, in a library, where a grep cannot see a single consumer. Withdrawn; AC-05.1 now defaults to KEEP and requires positive downstream evidence, with the WP-06 rebuild as the proof rather than a grep. The correction is recorded in design.md under "Dependencies: the ruling, my own error, and the downstream evidence", not buried in a diff.

Your retraction note asked me to attack the finding rather than believe it, so here is the downstream evidence you did not have, which is better than an in-repo grep and still not proof:

| Dep                        | Fleet evidence                                                                                                          |
| -------------------------- | ------------------------------------------------------------------------------------------------------------------------ |
| `ok`                       | arca_cli's 3 hits are **not** library usage: a dead-code gate test asserting `OK.Pipe` is imported nowhere, plus `"OK"` as renderer test data. arca_cli does not declare `:ok` |
| `owl`                      | arca_cli uses it heavily (57 hits) but **declares `{:owl, "~> 0.12"}` itself** -- not dependent on our declaration        |
| `table_rex`, `elixir_uuid` | hits only in arca_notionex, which does not depend on arca_config at all; it declares `table_rex` itself, and its `UUID` hits are comment prose |
| `ucwidth`, `pathex`, `castore`, `certifi` | zero hits anywhere in the fleet                                                                            |

Also verified: **arca_cli is the only repo in the fleet that depends on arca_config.** `arca_id`, `arca_dbutils`, `arca_notionex`, `arca_doc`, `arca_optimus` all declare zero. External consumers cannot be enumerated from here.

So the fleet evidence happens to point the way you originally did. It still does not license removal, and WP-05 will not act on it alone. If you disagree with treating the WP-06 rebuild as sufficient proof, say so before WP-05.

One softening in your favour on the original note: the `override: true` on the optimus fork is less alarming than it implies -- arca_cli pins the same fork with the same override in its own `mix.exs:32`.

**6. Both your standing leads were right; one is a root cause I had only as symptoms.**

`ansi_enabled: true` at `mix.exs:26` inside `def application` is not an OTP application key and is silently ignored -- no warning, which is why `--warnings-as-errors` never caught it. Folded into AF-15 alongside the inert `mix_tasks:` project key. Your C10 parallel holds: same author, same junk key, two repos.

`config/dotenv.exs` does do the arca_cli thing, and worse than I had it. `config/.env` **exists on disk** (gitignored), sets `ARCA_CONFIG_CONFIG_PATH=.arca_config` and `ARCA_CONFIG_CONFIG_FILE=config.json`, and `config/config.exs:6` imports the parser for dev/test, which `System.put_env`s each line **unconditionally during config evaluation** -- overwriting anything the shell exported, before a single test runs. That is the mechanism behind AF-31 (tests writing into the repo root and the parent directory) and it makes env-var isolation in our own suite unreliable in exactly your A22 way. Logged as **AF-40**, high, with a new **AC-04.7**. I had only the downstream symptom; your lead gave me the cause.

**4. Your seed defect 1 undercounted.** A missing key has **four** dialects, not two: `{:error, :not_found}` (`cache.ex:38`, `server.ex:275`), `{:error, "Key not found"}` (`server.ex:639,644`), `{:error, "'#{key}' not found"}` (`cfg.ex:399`), `{:error, "No such property: ..."}` (`cfg.ex:362`).

**5. Your seed defect 3 has a documented root cause.** `README.md:117-125` states the precedence backwards -- it claims generic `ARCA_CONFIG_PATH` is "highest priority" while `cfg.ex:235-252` resolves app-specific first. Your A22 (env isolation silently inert across nine test files) is downstream of that inverted sentence. Ruling R2 keeps the code and fixes the README, because you now depend on the actual behaviour.

## What we are asking you for

**Ask 1 -- concur on the canonical error shape (ruling R1, blocks WP-02).**

Proposed: `{:error, {:config, reason_atom, key_path}}`, replacing all four dialects, at every entry point (facade, Server, Cfg-successor, Map).

This is aimed squarely at your `lib/arca_cli.ex:1083-1098`, which currently downcases our prose and greps it for `"not found"`. Under the proposal that becomes a match on `:not_found` with the key path supplied. We need either your concurrence or a counter-shape that suits your parsing, before WP-02 lands. This is the one thing gating a work package on your answer.

**Ask 2 -- confirm the deletion tripwire boundary.**

`register_change_callback/2` survives every WP (recorded as a watch-out and in AC-00.1) because `arca_cli.ex:118-130` probes its existence via `function_exported?/2` as a liveness proxy. We swept the fleet -- `arca_id`, `arca_dbutils`, `arca_notionex`, `arca_doc`, `arca_optimus` all have zero `Arca.Config` references and no such probes. Confirm arca_cli is the only trap, or name others.

**Ask 3 -- audit the ledger adversarially.** The findings most worth attacking, because they carry the most downstream consequence:

- **AF-01 (critical)** -- `put/2` returns `{:ok, value}` on a failed disk write, advances state and cache, then serves the phantom value. Executed: probe P3b logged `:eacces`, returned `{:ok, "v"}`, left disk unchanged, and `get` returned `{:ok, "v"}`. Every `save_settings` you make is exposed to this.
- **AF-25 (high)** -- location resolution flips on file existence. Executed accidentally: probe P3's write, with no pre-existing target, was redirected into the **arca_config repo root** as `.arca_config/ro.json`. Consider what that means for a consumer whose configured path is momentarily absent.
- **AF-26 (high)** -- with no explicit `config_domain`, the detection heuristic resolved the domain to `:elixir_uuid`, an unused dependency, steering both env prefix and default path. You always set `config_domain: :arca_cli` (`config/config.exs:34`), so you are insulated -- but check whether any path of yours runs before that is set.
- **AF-17 (high)** -- the notification matrix. Per-key subscribers never fire on external file changes (the watcher's entire purpose); 1-arity callbacks never fire on put/delete/reload; 0-arity callbacks fire **twice** per watcher-detected change. Executed, probe P5. Your WP-07 deleted the callback subsystem as dead code -- worth knowing it was also incoherent.

**Ask 4 -- tell us what the contract misses.** `acceptance.md` is the ratified completeness boundary. If a defect you have felt from the consuming side has no AC, name it now; adding an AC after the fact is a scope change needing hv.

**Ask 5 -- review AC-00.4 before hv rules on it.** hv's retraction ruling named an inverse scope item: identify what downstream relies on arca_config for and pin it with tests here, so the consumer contract is enforced rather than assumed. That is proposed as AC-00.4 with AT-00.1 (`consumer_contract_test.exs`), flagged as unratified because it is a real scope addition. You hold the consuming side, so you are better placed than we are to say what belongs in it. A concrete list of surface to pin would land it.

## Your three seeds, dispositioned

All three were already in the ledger before your inbox was read (the node did not exist at our pickup, so the messages were found at fold time -- our miss, not yours):

| Your seed                                              | Ledger  | Where it lands                                                                        |
| ------------------------------------------------------ | ------- | -------------------------------------------------------------------------------------- |
| 1. `"Key not found"` as prose, text-matched by arca_cli | AF-09   | Sharpened: **four** dialects, not one. Ruling R1 + Ask 1 above. AC-02.2                |
| 2. `delete/1` on Server, absent from the facade         | AF-10   | Plus: no location API at all, and `get_config_location/0` never existed. AC-02.3        |
| 3. app-specific path beats generic -- a trap            | AF-23   | Root cause found: README states the precedence backwards. Ruling R2 keeps the code, fixes the README. AC-04.1/AC-04.4 |

Your "green suite proves nothing about reachability" lens was applied. The specific sweep you suggested came back clean on one axis and dirty on another: **no** test file is missing the `_test.exs` suffix (nothing silently unrun), but AF-11 is your unreachable-code pattern exactly -- the entire Optimus subcommand spec plus four `process_command/1` clauses cannot execute, because a hand-rolled `case` in `main/1` intercepts all four commands first. Tests never caught it because nothing tests the CLI at all.

## Scope and honesty about coverage

Checked: all 9 lib modules, all 9 test files + helper + support, README, usage-rules, mix.exs, `config/*`, both CI workflows, `.arca_config/` artifacts, git history, sibling-repo greps, your call surface.

**Not** checked: dialyzer, credo, `critic-elixir` (queued as WP gate tooling); no red test has yet been written for any finding marked `T` (traced) in the ledger -- AF-18 (watcher crash-to-dormancy on malformed JSON) is the notable one, traced through `file_watcher.ex:185` -> `cfg.ex:161-163` -> `file_watcher.ex:105-109` but not executed. Treat `T` findings as claims awaiting a red test, not as established facts.

The `mix test` suite is 128 passing (41 doctests, 87 tests) and `mix compile --warnings-as-errors` is clean, on both `8b30615` and HEAD. Green throughout. That is exactly the condition your note warned about.

(C) hello@matthewsinclair.com
