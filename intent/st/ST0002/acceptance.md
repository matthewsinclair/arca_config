---
st_id: ST0002
title: Fable review of arca_config base code
---

# ST0002: Fable review of arca_config base code -- Acceptance

> **THIS FILE IS A GENERATED VIEW, AND A ROW AUTHORED HERE IS DISCARDED BY THE NEXT SYNC.** The acceptance contract is canon in the thread model; this file renders it. Acceptance Criteria (AC) are the ratified completeness boundary; Acceptance Tests (AT) are the small red-to-green tests that prove them.
>
> Done = every AC is covered by a GREEN AT, or (for a non-test AC) its named evidence is satisfied, AND the AC set is the ratified full boundary. Done is read from this map, never from a hand-ticked box.
>
> Test-backed satisfaction is COMPUTED from covering green ATs and never stored -- storing it would be double truth. An AC has four states, not two: beyond satisfied and unsatisfied, a requirement can be **descoped** to a named thread or **withdrawn** with its reason on the record. Both are non-blocking and both are reported separately, so a thread that descoped half its contract looks like one.

## Acceptance Criteria

### ST-level

- AC-00.1 (non-test) No public symbol is retired without the sibling-fleet probe (`function_exported?` / `Code.ensure_loaded?` / direct refs) re-run at removal time and recorded -- the `register_change_callback/2` tripwire (arca_cli liveness proxy) survives or arca_cli is migrated first -- evidence: impl.md removal log + vc ack below -- satisfied: yes
- AC-00.2 (non-test) arca_cli rebuilt against the final arca_config (mix.lock advanced from 8b30615) and its full suite passes, executed by vc -- evidence: vc report at `intent/st/ST0002/vc-rebuild-report.md` -- satisfied: yes
- AC-00.3 (non-test) Every test changed because it asserted a defect is listed in impl.md's changed-tests ledger with before/after behaviour -- evidence: impl.md changed-tests ledger, 10 rows as at 2026-08-04, covering WP-01 (7), WP-02 (3) and WP-05 (2); re-checked at ST close because AC-02.2 will add rows -- satisfied: yes
- AC-00.4 (RATIFIED by hv 2026-08-04 -- scope addition accepted, contract is 38) What downstream relies on arca_config for is identified and pinned by tests **here**, so the consumer contract is enforced rather than assumed. Arises from hv's ruling on the dependency retraction: in-repo silence over public surface signals untested contract surface, and the remedy is coverage, not deletion. Covered by AT-00.1 -- satisfied: yes (computed)

### WP-01 -- Truthful returns: persistence failures surface (status: Done)

- AC-01.1 `put/2` and `delete/1` return `{:error, _}` when persistence fails, and neither server state nor cache advances past the failed write (a subsequent `get` reflects disk, not the phantom value) -- satisfied: yes (computed)
- AC-01.2 `put!/2` and `delete!/1` raise on persistence failure -- satisfied: yes (computed)
- AC-01.3 A failed initial/on-demand config load surfaces as a load error to the caller, not as "key not found" for every key thereafter -- satisfied: yes (computed)
- AC-01.4 Cache API clauses that fabricate success when the cache is unavailable are removed; cache unavailability is an honest failure distinct from key-miss -- satisfied: yes (computed)
- AC-01.5 A failed env-override application is surfaced (aggregate result from `load_config_phase/0`), not silently dropped -- satisfied: yes (computed)
- AC-01.6 (ruling R4) `switch_config_location/1` to a nonexistent path returns an error and leaves the previous location live; enoent-as-empty-config survives only for the documented first-run bootstrap path -- satisfied: yes (computed)

### WP-02 -- One lookup path, one dialect, complete facade (status: Done)

- AC-02.1 Exactly one nested get/put/delete/write implementation remains; every public write path registers the watcher write-token exactly once (no self-notification fork) -- the token clause is moot: WP-03 removed the token mechanism, so AT-02.1 pins the behaviour it protected -- satisfied: yes (computed)
- AC-02.2 (ruling R1) A missing key yields one canonical machine-matchable error shape from every entry point (facade, Server, Cfg-or-successor, Map); the four current dialects are gone -- satisfied: yes (computed)
- AC-02.3 The facade exposes `delete/1`, `delete!/1`, and a location-inspection API (`get_config_location/0` returning path, file, and source) such that arca_cli's `cli_command_helper.ex:350` call works unmodified -- satisfied: yes (computed)
- AC-02.4 (ruling R7) `Access.pop/2` and `get_and_update/3`'s `:pop` actually delete through the one write path, or the Access implementation is removed -- satisfied: yes (computed)
- AC-02.5 The dead `{:ok, conf}` clause in `notify_external_change/0` is gone, `:get_config` has a single reply shape, and no test mocks GenServer to reach dead code -- satisfied: yes (computed)

### WP-03 -- Notification and watcher coherence (status: Done)

- AC-03.1 A ratified notification matrix (channels x mutation paths) is implemented: each channel fires exactly once per mutation event on every path it covers, and the covered set is documented on `subscribe/1`, `register_change_callback/2`, and `add_callback/1` -- satisfied: yes (computed)
- AC-03.2 Per-key subscribers are notified on external file changes (the watcher's reason to exist) and on reload/switch, per the ratified matrix -- satisfied: yes (computed)
- AC-03.3 0-arity callbacks fire exactly once per externally-detected change (double-fire eliminated) -- satisfied: yes (computed)
- AC-03.4 The watcher survives malformed JSON: parse failure logs, retains last-good state, keeps watching (no crash-to-dormancy); recovery detects the next valid write -- satisfied: yes (computed)
- AC-03.5 An external edit landing inside the post-write suppression window is not lost (token identity compared, or equivalent re-check) -- satisfied: yes (computed)
- AC-03.6 After `put/2` returns, a `get/1` of any ancestor of the written path reflects the write (cache coherence) -- satisfied: yes (computed)

### WP-04 -- Location model: precedence, domain, isolation (status: Done)

- AC-04.1 (ruling R2) Precedence is ruled, implemented, and documented identically in README and moduledoc, with a single test asserting the full chain end-to-end -- satisfied: yes (computed)
- AC-04.2 `config_domain/0` is deterministic: explicit configuration or a documented stable default; the started-applications heuristic (probe P1: `:elixir_uuid`) is removed -- satisfied: yes (computed)
- AC-04.3 Location resolution is stable within a session: no file-existence flip between reads and writes -- satisfied: yes (computed)
- AC-04.4 (non-test) README matches behaviour: precedence order, actual default paths (CWD-relative or ruled otherwise), `.env` section corrected to project-local scope, one version string -- evidence: README diff reviewed against AC-04.1 test; precedence table now matches `Cfg`'s moduledoc and the test line for line, the location story says CWD-relative, the `.env` section says plainly that it is this repo's own dev setup and not a library feature, and the version lives only in mix.exs (`config.exs`'s copy removed, the CLI spec reads `Application.spec/2`, README's two install blocks reconciled) -- satisfied: yes
- AC-04.5 After `mix test`, the repo tree is clean: no writes to the repo root, its parent, or HOME; `git status --porcelain` empty; env mutations restored exactly (superset-restore fixed; doctests clean up) -- satisfied: yes (computed)
- AC-04.6 (non-test) Each remaining `async: false` carries a reason comment, or the module is `async: true` -- evidence: grep over test/ -- satisfied: yes
- AC-04.7 `config/.env` no longer overrides shell-exported config vars during config evaluation: an env var exported by the developer or CI wins over the checked-in dev default, and the resolution path is identical on a fresh clone (which has no `config/.env`) -- satisfied: yes (computed)

### WP-05 -- Surface and dependency pruning (status: Done)

- AC-05.1 Every dependency removal carries positive downstream evidence and is proven by the WP-06 arca_cli rebuild; **the default is KEEP**. In-repo non-reference is not grounds for removal (hv ruling on the dependency retraction: unreferenced-here over public surface means untested contract surface, not dead surface). A dep with no downstream evidence either way stays, and gets a note in impl.md rather than a deletion -- satisfied: yes (computed)
- AC-05.2 Test backdoors (`{:reset_for_test, ...}`, `{:reset_to_dormant, ...}`) are out of production modules, with equivalent test control via supervised lifecycle -- satisfied: yes (computed)
- AC-05.3 (ruling R3) The CLI ruling is executed: either a single dispatch path through the Optimus spec in an extracted module, or the escript is removed; no unreachable command spec remains -- satisfied: yes (computed)
- AC-05.4 (non-test) One CI workflow, matrix per ruling R6 -- evidence: `test.yml` deleted, `ci.yml` rewritten as one matrix (1.18.0/OTP 27, 1.18.4/OTP 28, 1.20.2/OTP 29 per R6), and both workflows' `ARCA_CONFIG_CONFIG_PATH: .arca_config` removed (2026-08-04; green run pending the next push, which is hv's to observe) -- satisfied: yes
- AC-05.5 (non-test) Cruft removed from version control -- evidence: `git rm` of four `.arca_config/` artifacts (including a 2024 OAuth config and a probe's `write_test.json`), three March-2025 debug scripts, and `.github/workflows/test.yml`; the commented-out `optimus` hex line; `.arca_config/` added to `.gitignore`. `AGENTS.md.bak` and `.backup/` were already untracked and ignored, so there was nothing to remove from version control (2026-08-04) -- satisfied: yes
- AC-05.6 The facade module contains delegation and documentation only; CLI/conversion/watch-loop logic lives elsewhere; critic-elixir pass on changed files is clean at severity >= warning -- satisfied: yes (computed)

### WP-06 -- Downstream verification and release (status: Not Started)

- AC-06.1 (non-test) vc's rebuild of arca_cli against the final arca_config passes its full suite; failures triaged to migration notes or fixed here -- evidence: vc report cited in impl.md -- satisfied: yes
- AC-06.2 (non-test) Migration notes list every breaking change with the replacement API -- evidence: CHANGELOG.md, written 2026-08-04, with a per-area breakdown, before/after error shapes, and an arca_cli section carrying the exact clause its rebuild needs. **Corrected while writing it**: the AC named "three arca_cli defensive strata now removable (error-prose matcher, Server.delete bypass, get_config_location shim)" and only the first exists. A grep of arca_cli/lib finds no delete bypass and no location shim -- satisfied: yes
- AC-06.3 (non-test) CHANGELOG + version bump per ruling R5 + tag by hv -- evidence: CHANGELOG.md written and version bumped to 0.3.0 in mix.exs and README; annotated tag `v0.3.0` created at hv's instruction 2026-08-04 and pushed to upstream, pointing at `ccd8fb5` -- satisfied: yes
- AC-06.4 (non-test) `usage-rules.md` (or successor consumer doc) carries actual arca_config API guidance for consumer LLM sessions -- evidence: rewritten 2026-08-04 (AF-39). It now leads with a consumer DO/NEVER contract -- satisfied: yes

## Acceptance Tests

### ST-level

- AT-00.1 `test/config/consumer_contract_test.exs` -- covers AC-00.4 -- status: green -- eight tests, each citing the arca_cli file:line that makes the call; red-first on the facade gap, closed by AC-02.3 in the same commit

### WP-01 -- Truthful returns: persistence failures surface (status: Done)

- AT-01.1 (legacy) test/config/server_test.exs::"put returns error and preserves state on unwritable location" (+ the delete twin) -- covers AC-01.1 -- status: green
- AT-01.2 (legacy) test/config/server_test.exs::"put!/delete! raise on persistence failure" -- covers AC-01.2 -- status: green
- AT-01.3 (legacy) test/config/server_test.exs::"failed load surfaces as load error not key-miss" -- covers AC-01.3 -- status: green
- AT-01.4 (legacy) test/config/cache_test.exs::"cache unavailability is distinct from key-miss" -- covers AC-01.4 -- status: green
- AT-01.5 (legacy) test/config/phase_based_test.exs::"failed override surfaces from load_config_phase" -- covers AC-01.5 -- status: green
- AT-01.6 (legacy) test/config/switch_location_test.exs::"switch to nonexistent path errors and preserves location" -- covers AC-01.6 -- status: green

### WP-02 -- One lookup path, one dialect, complete facade (status: Done)

- AT-02.1 (legacy) test/config/server_test.exs::"a write through Cfg has the same effect as a write through Server" (+ the read sibling) -- covers AC-02.1 -- status: green -- disk, cache and subscribers move together on every public write -- (red-first). Restated: the AC asked for the watcher write-token to be registered once per path, and WP-03 removed the token mechanism outright, so the AT pins the behaviour the token existed to protect
- AT-02.2 `test/config/error_dialect_test.exs` -- covers AC-02.2 -- status: green -- twelve tests, nine red first: the shape from all four entry points, the key path in the error, the cause preserved on load and parse failures, the rendering, and the two shapes that deliberately stay as they are
- AT-02.3 (legacy) covered by AT-00.1 in test/config/consumer_contract_test.exs::"the facade exposes the location and delete API its docs promise" -- covers AC-02.3 -- status: green -- (red-first). Folded into the consumer contract module rather than a separate facade_test.exs: the reason the facade needs these is that a consumer expects them, so the assertion belongs where the consumer contract lives
- AT-02.4 (legacy) test/config/map_test.exs::"pop deletes through the one write path" (+ missing-key and get_and_update siblings) -- covers AC-02.4 -- status: green -- red-first
- AT-02.5 (legacy) test/config/server_test.exs::"the :get_config call answers with the config map itself" (+ the notify_external_change sibling) -- covers AC-02.5 -- status: green -- Characterisation rather than red-first, stated plainly: the substance of this AC is removing an unreachable clause and the mock that fabricated a reply to reach it, so the AT holds the real behaviour across the removal rather than failing before it

### WP-03 -- Notification and watcher coherence (status: Done)

- AT-03.1 (legacy) test/config/notification_matrix_test.exs::"matrix: each channel fires once per covered path" -- covers AC-03.1, AC-03.2, AC-03.3 -- status: green -- with nine siblings in the same module walking reload, external detect and switch, the ancestor-replacement case, the unchanged-value cases, and the two re-entrancy pins
- AT-03.2 (legacy) test/config/file_watcher_test.exs::"watcher survives malformed JSON and recovers" -- covers AC-03.4 -- status: green
- AT-03.3 (legacy) test/config/file_watcher_test.exs::"external edit within post-write window is detected" -- covers AC-03.5 -- status: green
- AT-03.4 (legacy) test/config/server_test.exs::"ancestor get reflects nested put (cache coherence)" -- covers AC-03.6 -- status: green

### WP-04 -- Location model: precedence, domain, isolation (status: Done)

- AT-04.1 (legacy) test/config/cfg_test.exs::"precedence chain end-to-end" -- covers AC-04.1 -- status: green
- AT-04.2 (legacy) test/config/cfg_test.exs::"config_domain deterministic without heuristic" -- covers AC-04.2 -- status: green
- AT-04.3 (legacy) test/config/cfg_test.exs::"location stable across file creation" -- covers AC-04.3 -- status: green
- AT-04.4 (legacy) **test/isolation_test.exs**::"suite leaves repo tree and env exactly as found" -- covers AC-04.5 -- status: green -- path clarified from `test/support/isolation_check.exs`: ExUnit only runs `*_test.exs` under `test/`, so the drafted path would never have executed -- vc's own reachability lens, applied to my own contract. The comparison helper lives at `test/support/isolation.ex` and the standing guard is in `test/test_helper.exs`
- AT-04.5 (legacy) test/config/cfg_test.exs::"shell-exported config var beats the checked-in dev default" -- covers AC-04.7 -- status: green

### WP-05 -- Surface and dependency pruning (status: Done)

- AT-05.1 (legacy) test/config/production_surface_test.exs::"the library ships no production modules that answer test-only messages" (+ the scan-coverage and public-API siblings) -- covers AC-05.2 -- status: green -- Structural on purpose and stated as such: with the clause gone the old message matches no `handle_info/2` and kills the process, so a behavioural test here would have to assert a crash
- AT-05.2 `test/config/cli_test.exs` -- covers AC-05.3 -- status: green -- eight tests, every one through `main/1`, so a specification that stopped matching fails them; includes the multi-word `set`, the coercion, and the list-as-chardata fix
- AT-05.3 `test/deps_audit_test.exs` -- covers AC-05.1 -- status: green -- the inference hv overruled, encoded as CI, and in direct contradiction of AC-05.1 as rewritten. It now names all thirteen dependencies with the reason each is kept and fails when one is added or removed without saying which -- **restated**. As drafted it asserted declared == referenced, which would fail the build for any dependency with no in-repo call site
- AT-05.4 (legacy) (gate) critic-elixir clean at >= warning on changed files -- covers AC-05.6 -- status: green -- Run 2026-08-04 at hv's instruction: 9 critical + 12 warning, all 21 closed, including a Protocol.UndefinedError that AC-02.2 had shipped an hour earlier on every error path. Four of the criticals were findings the Fable audit missed (C1 data loss on the write path, C3, C4, C5). Detail in impl.md; ten further ledger rows. The structural half of AC-05.6 is green in test/config/production_surface_test.exs::"the facade holds no CLI, conversion or watch-loop logic"

### WP-06 -- Downstream verification and release (status: Not Started)

_(no tests in this group)_

---

_Generated by Intent v3.0.0 from `thread.json`. Do not edit this file -- it is rendered from the model, and `intent doctor` reports any hand-edit as skew._
