---
node: vc
name: Validation Claude
role: validation
session_id: 7a8b32c5-d7d6-4fa9-912b-4e0df57131fb
heartbeat_at: 2026-08-04T21:50Z
status: paused
focus: "RELEASE COMPLETE. ST0002 DONE 38/38, v0.3.0 tagged. vc released"
claims: []
---

# Validation Claude (vc)

## DOING

- Node provisioned (hv, 2026-08-04): one vc session validates BOTH arca_cli and
  arca_config. Same `session_id` appears on both boards -- that is one session
  wearing two hats, not a stale copy.
- **WP-01 / WP-03 / WP-04 all verified PASS** (2026-08-04 19:25, at 8d82cf4).
  152 green x seeds 1/42/7777/314159/982300/8888. Verdict in cc/inbox.vc.md.
- **Ask 1 answered: CONCUR** on `{:error, {:config, reason_atom, key_path}}`, with
  one amendment (carry canonical prose alongside the atom, or every consumer grows
  its own atom-to-prose table and the four dialects reappear a layer up). WP-02 is
  unblocked on my side.

## TODO

- **VERIFY WP-02 partial (f3aad5f) and WP-05 (284a803) -- claimed, NOT yet checked.**
  Contract 30/38, suite 188 green claimed. Highest-value target is `Cfg.get/put`
  now delegating to `Server`: cc found six green seeds hid an ordering bug that a
  single unseeded run exposed. Seeds prove order-independence, not correctness --
  run unseeded and in a fresh order, not just more seeds.
- Also unverified: the WP-05 removals (escript target, two GenServer backdoors,
  repo artifacts) and `deps_audit_test.exs` naming all thirteen deps with reasons.
- **AC-00.2 rebuild**: run the arca_cli harness with `--local-config` against
  arca_config's tree once cc@arca_cli's in-flight A29 work lands. Blocked only on
  the shared build lock, not on anyone's decision.
- WP-02 verification when claimed (the error-shape change; it lands on
  `arca_cli.ex:1083-1098`, so verify the arca_cli side too, not just this repo).
- WP-05 waits on hv's R3. WP-06 is the downstream-rebuild proof -- insist it uses
  BEHAVIOURAL probes with a missing config, not a green arca_cli suite. I proved
  the suite stays green through these changes while missing-config behaviour
  changes materially.
- Dependency question: cc's fleet-wide grep is better evidence than anything
  either of us ran before, and it points where I originally did. Still hv's call,
  not mine and not cc's -- hv ruled KEEP on this exact question.

## Verified myself (2026-08-04, at 8d82cf4)

- 152 green (41 doctests, 111 tests), 6 seeds. Matches cc's claim exactly.
- **Isolation, with a sharper instrument than the seed sweep that fooled cc**:
  recursive file listing of repo AND parent, before/after, diffed -- plus an
  md5-of-md5s over `.arca_config` contents to catch in-place mutation a listing
  cannot see. Zero new files either side; config dir byte-identical.
- `.env` precedence fixed (my lead): exported var survives, default still applies.
- Env-var precedence: domain-specific beats generic, driven not read. Documented
  identically in README:118-123, `cfg.ex:16-24`/`:140-144`, `cfg_test.exs:90`.
- `config_domain/0` heuristic gone; `$callers` survives only as a comment.
- WP-03 loop pins: no deadlock on callback-write; derived-value callback settles
  at 2 fires. A non-convergent callback still loops -- a bound to state in the AC,
  NOT a defect (no suppression rule can converge a value with no fixed point).

## Baseline (mine, independently measured -- 2026-08-04, at 9925115)

- `mix compile --force --warnings-as-errors`: clean, 9 lib files.
- `mix test --seed 31`: 128 passed (41 doctests, 87 tests), 0 failures, 1.4s.
- Matches cc's claimed baseline exactly. Any regression is measured against this.

## Verification lenses (OPEN -- this board is world-readable to peers by protocol)

The header here used to read "held privately -- do NOT feed to cc". That was
self-deception: pickup reads peer boards, so it was never private, only labelled.
cc read it and said so rather than quietly benefiting -- the right call, and the
correction is mine to take. A genuinely blind lens cannot live in `wip.md` at all.
Lenses kept here from now on are ones I am content for cc to see.

- All test modules declared `async: false` (was 9/9, now 11/11). RESOLVED in
  WP-04: each now carries a specific reason naming the global state it touches,
  and the location model being process-global is AR-4's own finding rather than
  something a WP could remove. Reads as per-module judgement now, not copy-paste.

## Watch-outs

- No `hv` node on this board and no `README.md` roster (cc flagged both). Peer
  discovery is directory-listing only; escalations go to hv in-session.
- arca_config is a DEPENDENCY of arca_cli. A change here can break arca_cli
  0.5.0's ratified behaviour -- specifically its error dialect (see the seeds in
  cc's inbox). Any change to error shapes or the config-path precedence needs an
  arca_cli regression check before it lands.
- `Arca.Config.Cfg` is aliased `LegacyCfg` in `server.ex:16` but is still the
  live loader with public doctests (cc's finding). Ambiguous ownership; do not
  assume dead code.

## Decisions

- (2026-08-04) A "private" section on a shared board is not private. cc read my
  lenses block by protocol and disclosed it. Anything genuinely blind stays out of
  `wip.md` entirely; everything on the board is written as if cc will read it,
  because cc will.
- (2026-08-04) A green downstream suite is NOT downstream evidence. arca_cli held
  at 764 green across arca_config's WP-01/03/04 while its missing-config behaviour
  changed materially -- because nothing exercised that path. AC-05.1's proof must
  be behavioural probes, not a passing suite. Same archetype as the whole ST0011
  thread, now at the repo boundary.
- (2026-08-04) Verification method carried from ST0011, unchanged: fire on
  claim, read the as-built not the narrative, every finding carries file:line,
  self-refute HIGH findings first, and state coverage gaps explicitly.
- (2026-08-04) RETRACTED my own first finding here, by hv. I reported 8 declared
  deps as unused chain-wide and implied they could be dropped; they are USED
  DOWNSTREAM. arca_config is a library and a zero-hit grep inside it cannot see
  a single consumer. Retraction is in cc/inbox.vc.md (16:13).
- (2026-08-04) STANDING LENS for this whole ST, from that error: in-repo silence
  over PUBLIC surface (deps, facade functions, exported helpers) is not evidence
  of deadness -- it is evidence of UNTESTED CONTRACT SURFACE. Remedy is tests
  that pin intended usage, not deletion. Applies doubly here: arca_config is
  consumed by arca_cli and others, so almost nothing public is safely judged
  from inside. Any deletion cc proposes needs downstream evidence, not a grep;
  I will hold its purge proposals to that standard and I will hold my own
  findings to it first.
