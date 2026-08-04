---
verblock: "04 Aug 2026:v0.4: matts - ST0002 contract RATIFIED; all seven rulings decided; WP-01/03/04 done, WP-02/05 partial"
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
> Ruling state (design.md carries the decisions): **all seven rulings are decided and executed.** R2, R4, R5, R6, R7 as proposed; R3 as *extract*; **R1's wire format settled 2026-08-04 by hv delegation** ("pick a sensible one"): `{:error, {:config, reason, detail}}`, arca_config first, with the arca_cli clause landing in the WP-06 rebuild that gates the release anyway.
>
> **Post-ratification amendments, 2026-08-04** (recorded rather than silently applied): AC-05.1 was rewritten after hv's ruling on vc's dependency retraction -- as ratified it inferred removability from in-repo non-reference, which is the inference hv overruled. It now defaults to KEEP and requires downstream evidence. AC-04.7 added (config/.env overriding shell env during config evaluation -- AF-40, from a vc lead, verified here). AC-00.4 was proposed as a genuine scope addition and **hv accepted it on 2026-08-04**; the contract is 38. hv also **ratified the notification matrix** in design.md that same day, closing the last gap in AC-03.1.

## Acceptance Criteria

### ST-level

- AC-00.1 (non-test) No public symbol is retired without the sibling-fleet probe (`function_exported?` / `Code.ensure_loaded?` / direct refs) re-run at removal time and recorded -- the `register_change_callback/2` tripwire (arca_cli liveness proxy) survives or arca_cli is migrated first -- evidence: impl.md removal log + vc ack -- satisfied: no
- AC-00.2 (non-test) arca_cli rebuilt against the final arca_config (mix.lock advanced from 8b30615) and its full suite passes, executed by vc -- evidence: vc report -- satisfied: no
- AC-00.3 (non-test) Every test changed because it asserted a defect is listed in impl.md's changed-tests ledger with before/after behaviour -- evidence: impl.md changed-tests ledger, 10 rows as at 2026-08-04, covering WP-01 (7), WP-02 (3) and WP-05 (2); re-checked at ST close because AC-02.2 will add rows -- satisfied: yes
- AC-00.4 (RATIFIED by hv 2026-08-04 -- scope addition accepted, contract is 38) What downstream relies on arca_config for is identified and pinned by tests **here**, so the consumer contract is enforced rather than assumed. Arises from hv's ruling on the dependency retraction: in-repo silence over public surface signals untested contract surface, and the remedy is coverage, not deletion. Covered by AT-00.1

### WP-01 -- Truthful returns (status: DONE 2026-08-04, all six ATs green)

- AC-01.1 `put/2` and `delete/1` return `{:error, _}` when persistence fails, and neither server state nor cache advances past the failed write (a subsequent `get` reflects disk, not the phantom value)
- AC-01.2 `put!/2` and `delete!/1` raise on persistence failure
- AC-01.3 A failed initial/on-demand config load surfaces as a load error to the caller, not as "key not found" for every key thereafter
- AC-01.4 Cache API clauses that fabricate success when the cache is unavailable are removed; cache unavailability is an honest failure distinct from key-miss
- AC-01.5 A failed env-override application is surfaced (aggregate result from `load_config_phase/0`), not silently dropped
- AC-01.6 (ruling R4) `switch_config_location/1` to a nonexistent path returns an error and leaves the previous location live; enoent-as-empty-config survives only for the documented first-run bootstrap path

### WP-02 -- One lookup path, one dialect, complete facade (status: DONE 2026-08-04, all five ACs green)

- AC-02.1 Exactly one nested get/put/delete/write implementation remains; every public write path registers the watcher write-token exactly once (no self-notification fork) -- the token clause is moot: WP-03 removed the token mechanism, so AT-02.1 pins the behaviour it protected
- AC-02.2 (ruling R1) A missing key yields one canonical machine-matchable error shape from every entry point (facade, Server, Cfg-or-successor, Map); the four current dialects are gone
- AC-02.3 The facade exposes `delete/1`, `delete!/1`, and a location-inspection API (`get_config_location/0` returning path, file, and source) such that arca_cli's `cli_command_helper.ex:350` call works unmodified -- satisfied: yes (2026-08-04; pinned by AT-00.1)
- AC-02.4 (ruling R7) `Access.pop/2` and `get_and_update/3`'s `:pop` actually delete through the one write path, or the Access implementation is removed
- AC-02.5 The dead `{:ok, conf}` clause in `notify_external_change/0` is gone, `:get_config` has a single reply shape, and no test mocks GenServer to reach dead code

### WP-03 -- Notification and watcher coherence (status: DONE 2026-08-04, all four ATs green)

- AC-03.1 A ratified notification matrix (channels x mutation paths) is implemented: each channel fires exactly once per mutation event on every path it covers, and the covered set is documented on `subscribe/1`, `register_change_callback/2`, and `add_callback/1`
- AC-03.2 Per-key subscribers are notified on external file changes (the watcher's reason to exist) and on reload/switch, per the ratified matrix
- AC-03.3 0-arity callbacks fire exactly once per externally-detected change (double-fire eliminated)
- AC-03.4 The watcher survives malformed JSON: parse failure logs, retains last-good state, keeps watching (no crash-to-dormancy); recovery detects the next valid write
- AC-03.5 An external edit landing inside the post-write suppression window is not lost (token identity compared, or equivalent re-check)
- AC-03.6 After `put/2` returns, a `get/1` of any ancestor of the written path reflects the write (cache coherence)

### WP-04 -- Location model (status: DONE 2026-08-04, five ATs green + both non-test ACs evidenced)

- AC-04.1 (ruling R2) Precedence is ruled, implemented, and documented identically in README and moduledoc, with a single test asserting the full chain end-to-end
- AC-04.2 `config_domain/0` is deterministic: explicit configuration or a documented stable default; the started-applications heuristic (probe P1: `:elixir_uuid`) is removed
- AC-04.3 Location resolution is stable within a session: no file-existence flip between reads and writes
- AC-04.4 (non-test) README matches behaviour: precedence order, actual default paths (CWD-relative or ruled otherwise), `.env` section corrected to project-local scope, one version string -- evidence: README diff reviewed against AC-04.1 test; precedence table now matches `Cfg`'s moduledoc and the test line for line, the location story says CWD-relative, the `.env` section says plainly that it is this repo's own dev setup and not a library feature, and the version lives only in mix.exs (`config.exs`'s copy removed, the CLI spec reads `Application.spec/2`, README's two install blocks reconciled) -- satisfied: yes
- AC-04.5 After `mix test`, the repo tree is clean: no writes to the repo root, its parent, or HOME; `git status --porcelain` empty; env mutations restored exactly (superset-restore fixed; doctests clean up)
- AC-04.6 (non-test) Each remaining `async: false` carries a reason comment, or the module is `async: true` -- evidence: grep over test/ -- every one of the 11 modules carries a specific reason naming the global state it touches (config domain, location env vars, the named server/watcher/cache processes, the working directory), and none is boilerplate. All 11 stay `async: false`: the location model is still process-global, which is AR-4's own finding rather than something WP-04 could remove -- satisfied: yes
- AC-04.7 `config/.env` no longer overrides shell-exported config vars during config evaluation: an env var exported by the developer or CI wins over the checked-in dev default, and the resolution path is identical on a fresh clone (which has no `config/.env`)

### WP-05 -- Surface and dependency pruning (status: WIP -- AC-05.1/.2/.3/.4/.5 satisfied 2026-08-04; AC-05.6 awaits the critic-elixir pass)

- AC-05.1 Every dependency removal carries positive downstream evidence and is proven by the WP-06 arca_cli rebuild; **the default is KEEP**. In-repo non-reference is not grounds for removal (hv ruling on the dependency retraction: unreferenced-here over public surface means untested contract surface, not dead surface). A dep with no downstream evidence either way stays, and gets a note in impl.md rather than a deletion
- AC-05.2 Test backdoors (`{:reset_for_test, ...}`, `{:reset_to_dormant, ...}`) are out of production modules, with equivalent test control via supervised lifecycle
- AC-05.3 (ruling R3) The CLI ruling is executed: either a single dispatch path through the Optimus spec in an extracted module, or the escript is removed; no unreachable command spec remains
- AC-05.4 (non-test) One CI workflow, matrix per ruling R6 -- evidence: `test.yml` deleted, `ci.yml` rewritten as one matrix (1.18.0/OTP 27, 1.18.4/OTP 28, 1.20.2/OTP 29 per R6), and both workflows' `ARCA_CONFIG_CONFIG_PATH: .arca_config` removed -- it pointed inside the checkout, which is how CI runs wrote into the repository -- satisfied: yes (2026-08-04; green run pending the next push, which is hv's to observe)
- AC-05.5 (non-test) Cruft removed from version control -- evidence: `git rm` of four `.arca_config/` artifacts (including a 2024 OAuth config and a probe's `write_test.json`), three March-2025 debug scripts, and `.github/workflows/test.yml`; the commented-out `optimus` hex line; `.arca_config/` added to `.gitignore`. `AGENTS.md.bak` and `.backup/` were already untracked and ignored, so there was nothing to remove from version control -- recorded so the AC is not read as unfinished -- satisfied: yes (2026-08-04)
- AC-05.6 The facade module contains delegation and documentation only; CLI/conversion/watch-loop logic lives elsewhere; critic-elixir pass on changed files is clean at severity >= warning

### WP-06 -- Downstream verification and release (status: TODO)

- AC-06.1 (non-test) vc's rebuild of arca_cli against the final arca_config passes its full suite; failures triaged to migration notes or fixed here -- evidence: vc report cited in impl.md -- satisfied: no
- AC-06.2 (non-test) Migration notes list every breaking change with the replacement API -- evidence: CHANGELOG.md, written 2026-08-04, with a per-area breakdown, before/after error shapes, and an arca_cli section carrying the exact clause its rebuild needs. **Corrected while writing it**: the AC named "three arca_cli defensive strata now removable (error-prose matcher, Server.delete bypass, get_config_location shim)" and only the first exists. A grep of arca_cli/lib finds no delete bypass and no location shim -- the same over-claim as the handover note's `get_config_location` error, from the same source. One stratum, named accurately -- satisfied: yes
- AC-06.3 (non-test) CHANGELOG + version bump per ruling R5 + tag by hv -- evidence: CHANGELOG.md written and version bumped to 0.3.0 in mix.exs and README 2026-08-04; **the tag is hv's and has not been made** -- satisfied: no
- AC-06.4 (non-test) `usage-rules.md` (or successor consumer doc) carries actual arca_config API guidance for consumer LLM sessions -- evidence: file content review -- satisfied: no

## Acceptance Tests

### ST-level

- AT-00.1 test/config/consumer_contract_test.exs -- covers AC-00.4 -- status: green (eight tests, each citing the arca_cli file:line that makes the call; red-first on the facade gap, closed by AC-02.3 in the same commit)
- Coverage: AC-00.1/.2/.3 are non-test with evidence on the AC line; AC-00.4 covered by AT-00.1

### WP-01

- AT-01.1 test/config/server_test.exs::"put returns error and preserves state on unwritable location" (+ the delete twin) -- covers AC-01.1 -- status: green
- AT-01.2 test/config/server_test.exs::"put!/delete! raise on persistence failure" -- covers AC-01.2 -- status: green
- AT-01.3 test/config/server_test.exs::"failed load surfaces as load error not key-miss" -- covers AC-01.3 -- status: green
- AT-01.4 test/config/cache_test.exs::"cache unavailability is distinct from key-miss" -- covers AC-01.4 -- status: green
- AT-01.5 test/config/phase_based_test.exs::"failed override surfaces from load_config_phase" -- covers AC-01.5 -- status: green
- AT-01.6 test/config/switch_location_test.exs::"switch to nonexistent path errors and preserves location" -- covers AC-01.6 -- status: green
- Coverage: AC-01.1..6 each have an AT; none uncovered. All six were red first, each for the defect its design.md ledger row describes; landed 2026-08-04 (impl.md has the as-built and the changed-tests ledger).

### WP-02

- AT-02.1 test/config/server_test.exs::"a write through Cfg has the same effect as a write through Server" (+ the read sibling) -- covers AC-02.1 -- status: green (red-first). Restated: the AC asked for the watcher write-token to be registered once per path, and WP-03 removed the token mechanism outright, so the AT pins the behaviour the token existed to protect -- disk, cache and subscribers move together on every public write
- AT-02.2 test/config/error_dialect_test.exs -- covers AC-02.2 -- status: green (twelve tests, nine red first: the shape from all four entry points, the key path in the error, the cause preserved on load and parse failures, the rendering, and the two shapes that deliberately stay as they are)
- AT-02.3 covered by AT-00.1 in test/config/consumer_contract_test.exs::"the facade exposes the location and delete API its docs promise" -- covers AC-02.3 -- status: green (red-first). Folded into the consumer contract module rather than a separate facade_test.exs: the reason the facade needs these is that a consumer expects them, so the assertion belongs where the consumer contract lives
- AT-02.4 test/config/map_test.exs::"pop deletes through the one write path" (+ missing-key and get_and_update siblings) -- covers AC-02.4 -- status: green (red-first)
- AT-02.5 test/config/server_test.exs::"the :get_config call answers with the config map itself" (+ the notify_external_change sibling) -- covers AC-02.5 -- status: green. Characterisation rather than red-first, stated plainly: the substance of this AC is removing an unreachable clause and the mock that fabricated a reply to reach it, so the AT holds the real behaviour across the removal rather than failing before it
- Coverage: AC-02.1..5 each have an AT; none uncovered

### WP-03

- AT-03.1 test/config/notification_matrix_test.exs::"matrix: each channel fires once per covered path" -- covers AC-03.1, AC-03.2, AC-03.3 -- status: green (with nine siblings in the same module walking reload, external detect and switch, the ancestor-replacement case, the unchanged-value cases, and the two re-entrancy pins)
- AT-03.2 test/config/file_watcher_test.exs::"watcher survives malformed JSON and recovers" -- covers AC-03.4 -- status: green
- AT-03.3 test/config/file_watcher_test.exs::"external edit within post-write window is detected" -- covers AC-03.5 -- status: green
- AT-03.4 test/config/server_test.exs::"ancestor get reflects nested put (cache coherence)" -- covers AC-03.6 -- status: green
- Coverage: AC-03.1..6 covered (AT-03.1 covers .1/.2/.3); none uncovered. All red first; landed 2026-08-04. The matrix AC-03.1 calls "ratified" is in design.md and hv ratified it on 2026-08-04, so AC-03.1 is satisfied in full.

### WP-04

- AT-04.1 test/config/cfg_test.exs::"precedence chain end-to-end" -- covers AC-04.1 -- status: green
- AT-04.2 test/config/cfg_test.exs::"config_domain deterministic without heuristic" -- covers AC-04.2 -- status: green
- AT-04.3 test/config/cfg_test.exs::"location stable across file creation" -- covers AC-04.3 -- status: green
- AT-04.4 **test/isolation_test.exs**::"suite leaves repo tree and env exactly as found" -- covers AC-04.5 -- status: green (path clarified from `test/support/isolation_check.exs`: ExUnit only runs `*_test.exs` under `test/`, so the drafted path would never have executed -- vc's own reachability lens, applied to my own contract. The comparison helper lives at `test/support/isolation.ex` and the standing guard is in `test/test_helper.exs`)
- AT-04.5 test/config/cfg_test.exs::"shell-exported config var beats the checked-in dev default" -- covers AC-04.7 -- status: green
- Coverage: AC-04.1/.2/.3/.5/.7 test-covered; AC-04.4/.6 non-test with evidence on the AC line. All red first; landed 2026-08-04.

### WP-05

- AT-05.1 test/config/production_surface_test.exs::"the library ships no production modules that answer test-only messages" (+ the scan-coverage and public-API siblings) -- covers AC-05.2 -- status: green. Structural on purpose and stated as such: with the clause gone the old message matches no `handle_info/2` and kills the process, so a behavioural test here would have to assert a crash
- AT-05.2 test/config/cli_test.exs -- covers AC-05.3 -- status: green (eight tests, every one through `main/1`, so a specification that stopped matching fails them; includes the multi-word `set`, the coercion, and the list-as-chardata fix)
- AT-05.3 test/deps_audit_test.exs -- covers AC-05.1 -- status: green, **restated**. As drafted it asserted declared == referenced, which would fail the build for any dependency with no in-repo call site -- the inference hv overruled, encoded as CI, and in direct contradiction of AC-05.1 as rewritten. It now names all thirteen dependencies with the reason each is kept and fails when one is added or removed without saying which
- AT-05.4 (gate) critic-elixir clean at >= warning on changed files -- covers AC-05.6 -- status: to-write. Not run: it needs a subagent, which is hv's to authorise, so AC-05.6 stays unsatisfied. The structural half of AC-05.6 is green in test/config/production_surface_test.exs::"the facade holds no CLI, conversion or watch-loop logic"
- Coverage: AC-05.1/.2/.3/.6 covered; AC-05.4/.5 non-test with evidence on the AC line

### WP-06

- Coverage: all WP-06 ACs are non-test (vc-executed or hv-held); evidence named on each AC line
