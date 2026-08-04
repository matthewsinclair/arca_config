---
verblock: "04 Aug 2026:v1.0: matts - vc's AC-00.2 / AC-06.1 rebuild report"
st_id: ST0002
title: "arca_cli rebuild against arca_config 0.3.0 -- vc report"
---

# arca_cli rebuild against arca_config 0.3.0 -- vc report

Satisfies **AC-00.2** (rebuild executed, full suite passes) and **AC-06.1** (the report on it). Written by vc under release control handed over by hv on 2026-08-04. Every number here was measured by vc, not taken from a builder's claim.

## Verdict

**PASS, and the release is sound. One MED finding is filed rather than buried** -- see "The one thing I would not ship silently" below. It does not fail the suite, it is strictly better than the 0.4.x behaviour it replaces, and its fix is identified.

| | |
| --- | --- |
| arca_config | `5db55a4`, v0.3.0 tagged |
| arca_cli | `952667d`, after WP-15 absorbed the 0.3.0 error contract |
| Lock | advanced `8b30615` -> `03969fa` -> `5db55a4` (AC-00.2's condition) |
| Suite | **782 passed** (29 doctests, 753 tests), seeds 1/3/11/77/555/4242 |
| Contract | ST0011 57/57 PASS |
| Compile | `--warnings-as-errors` clean; `--check-formatted` clean |
| Escript | rebuilt from a forced prod compile; success paths exit 0 / zero `^error:`, failure paths exit 1 / exactly one |

## How this was verified

A green suite is not evidence that a dependency change is safe -- it only reports on the paths it reaches. arca_cli held at **764 green across arca_config's WP-01/03/04 while its missing-config behaviour changed materially**, because nothing in the suite exercised that path. So the rebuild was verified with a behavioural harness that drives the real escript, kept at `arca_cli/intent/whiteboard/vc/probes/`.

Three probes, captured before and after and diffed: an escript behaviour table (exit code, dialect lines, cross marks and *the text of the diagnosis*), a `channel x completion x style` matrix asserting `Ctx.outcome/1` still governs the error dialect, and the suite. Six invariants, of which D3 is the one that flips at the bump.

## What the bump fixed, measured

**The old arca_config was lying to arca_cli.** Pointed at a config path that does not exist, 0.4.x `cfg.list` and `settings.all` **exited 0 and printed a different config than the one asked for** -- the silent CWD fallback. WP-04's removal of that fallback is a correctness fix for this consumer, not tidying.

**The R1 migration is clean.** WP-15 absorbed `{:config, reason, detail}` at both seams, not just the one predicted in the handover: `setting_error/2` gained the canonical clause, and `reason_text/1` -- which was a silent duplicate of `ErrorHandler.format_reason/1` -- was **deleted** in favour of one `config_reason/1` delegating to `Arca.Config.Error.message/1`. That is the Highlander answer rather than a second patch.

**A29 is closed and driven.** A config that exists but does not parse now reports its real cause through to the user (`Error parsing config at position: 2, token: ''`) rather than the constant `"Unknown error loading settings"` with a raw `%MatchError{}` logged above it.

## The one thing I would not ship silently

**MED -- WP-15 re-swallows the missing-config signal, and the distinction it needs is available.**

`Arca.Cli.load_settings/0` now maps `{:error, {:config, :load_failed, :enoent}}` to `{:ok, %{}}`. Measured consequence with a config path that does not exist:

    MISSCFG  cfg.list      exit=0  "No configuration settings found."
    MISSCFG  settings.all  exit=0  "⚠ No settings available"

A user who mistypes `ARCA_CLI_CONFIG_PATH` is told their config is empty, not that their path is wrong. That is the shape of A22 -- the bug that cost this project a day, where isolation set an environment variable across nine files and silently never took effect.

**cc's reasoning is sound as far as it goes**: `run/1` loads settings for every command, so without the clause every invocation on a fresh install printed a warning about an entirely normal state, and arca_config's own R4 says a missing file *is* an empty config for the bootstrap caller. A config that exists and cannot be parsed still fails loudly, so A29 is not reopened.

**But enoent-on-a-configured-path and enoent-on-the-default are not the same event, and arca_config 0.3.0 already distinguishes them.** `Cfg.config_location/0` returns `source: %{path: path_source, file: file_source}` (`cfg.ex:305-316`) -- built as AC-02.3 precisely so a consumer can tell where a resolution came from. The fix is to treat enoent as an empty config only when the location came from the default, and to report it when the user named the path.

**Why it ships anyway**: 0.4.x was strictly worse on this path (it read a *different* config and reported its contents as yours). The residual is a narrower failure mode than the one being removed, it is documented, and the fix is identified above. Blocking an otherwise-sound release over it would be disproportionate. Filed for a fast follow rather than buried in a footnote.

## A finding against my own instrument

The harness graded this capture **PASS** on first run. It was wrong, and the way it was wrong is worth recording.

Its phase detection inferred "is D3 a hard gate or a known-red baseline?" from the capture's *label*, treating only `after*`/`post*` as a gate. The release capture was labelled `release`, so it was silently graded as a pre-bump baseline and reported PASS over the two re-swallowed rows above. **A naming convention decided whether an invariant was enforced, and the default branch was the lenient one.**

Fixed by inverting the default: anything not explicitly declared a baseline now gates. Proven on the unchanged artifacts -- `pre-bump` still PASS, `release` correctly reports 2 failures. The lesson is not that the inference was wrong but that its failure mode was *silent leniency*, which is the same defect class this whole thread has been removing, occurring inside the tool built to detect it.

## Coverage of this report

**Checked**: arca_cli's full suite across six seeds; compile and format gates; the escript end-to-end on 15 probe rows across success, failure, missing-config and corrupt-config; the `channel x completion x style` matrix; the ST0011 contract gate; and the public-symbol diff underlying the AC-00.1 ack.

**Not checked**: arca_notionex, which depends on arca_cli and which hv ruled out of scope -- a static surface check found no API breaks but it has not been compiled. I did not re-run arca_config's own suite as part of this report (it is cc's evidence, verified separately at 152 and later 212/222 green). I did not audit the three critic findings arca_config reports as this thread's lessons surviving in its tests; the equivalent sweep of arca_cli's suite is unstarted and is the most obvious next piece of work.
