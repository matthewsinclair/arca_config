# arca_config Usage Rules

Prescriptive DO / NEVER contract. The first half is for **projects that depend on arca_config** -- this is the file your LLM session reads at `deps/arca_config/usage-rules.md`. The second half is for working **on** arca_config itself.

## Using arca_config (consumers)

### Setup -- both steps are mandatory

DO set the config domain in your `Application.start/2`, **before** the supervision tree starts. It is never guessed. Without it the domain is `:arca_config`, so your configuration resolves to `.arca_config/` and reads `ARCA_CONFIG_*` variables rather than your own.

```elixir
def start(_type, _args) do
  Application.put_env(:arca_config, :config_domain, :my_app)
  Supervisor.start_link(children, opts)
end

def start_phase(:load_config, _start_type, _phase_args) do
  Arca.Config.load_config_phase()
end
```

DO declare `start_phases: [load_config: []]` in `application/0`. Configuration is loaded in that phase, not at supervision start; skip it and nothing is loaded.

### Errors

DO match the reason atom. Every failure is `{:error, {:config, reason, detail}}` -- `reason` is `:not_found`, `:load_failed` or `:write_failed`; `detail` is the key path for key-scoped failures and the underlying cause otherwise.

```elixir
case Arca.Config.get("database.host") do
  {:ok, host} -> host
  {:error, {:config, :not_found, _path}} -> "localhost"
  {:error, reason} -> raise Arca.Config.Error.message(reason)
end
```

NEVER match on error message text. It was four different sentences before 0.3.0 and matching prose is why that mattered. Use `Arca.Config.Error.message/1` when you need words for a human.

### Writes

DO handle `{:error, _}` from `put/2` and `delete/1`. They reach the disk, so they can fail -- before 0.3.0 they reported success regardless and served the phantom value from memory afterwards.

DO expect `delete/1` on a key that was never set to return `{:error, {:config, :not_found, path}}`. It is not a no-op success.

NEVER assume a write is repaired silently. If the config file exists but is not valid JSON, `put/2` and `delete/1` **refuse** rather than overwrite it.

### Where the configuration lives

DO use the domain-specific environment variables. With a domain of `:my_app`, `MY_APP_CONFIG_PATH` and `MY_APP_CONFIG_FILE` **outrank** the generic `ARCA_CONFIG_PATH` and `ARCA_CONFIG_FILE`. Setting only the generic pair while your application has a domain has no effect and fails silently -- this is the single most common way to lose an afternoon here.

DO call `Arca.Config.get_config_location/0` when resolution surprises you. It reports the path, the filename, the resolved file, and **which tier answered** for each (`:env_domain`, `:env_generic`, `:app_config`, `:default`).

DO use `switch_config_location/1` to move the location at runtime, and feed the value it returns back to it to restore. NEVER move it by setting environment variables behind the running server: reads come from the loaded configuration, so they will not follow until a `switch_config_location/1` or a `reload/0`.

### Change notifications

DO pick the channel by what you need: `subscribe/1` for one key (`{:config_updated, path, value}`), `register_change_callback/2` for the whole config map, `add_callback/1` when you only need to know that something changed. Each fires exactly once per change event, on writes, reloads, externally detected edits and location switches.

DO expect callbacks to be asynchronous -- they run off the server process, so a callback may not have run when `put/2` returns. Per-key subscriber messages are sent before the call returns.

NEVER expect an event from a write that changed nothing. That rule is what stops your own writes arriving back as external changes, and what stops a callback that writes a derived value from re-triggering itself forever.

### Testing against arca_config

DO set the **domain-specific** location variables in your test setup, and restore them exactly. DO use `switch_config_location/1` for per-test isolation; it returns the previous location for the `on_exit` restore.

NEVER point tests at a location inside your repository. This project learned that one the hard way: its own suite wrote into its working tree for months.

## Working on arca_config (contributors)

This project uses Intent v2.10.0. See `~/.intent/ext/`, `intent claude skills list`, and `intent claude subagents list` for the full Intent-provided surface.

- DO run `mix format` and `mix compile --warnings-as-errors` before every commit.
- DO keep suite output to dots only. Production logging a test provokes deliberately is captured with `ExUnit.CaptureLog` and asserted, never printed.
- DO restore anything global a test touches -- `test_helper.exs` fails the run if the suite changes the working tree, the config environment variables, or `:arca_config`'s application settings.
- NEVER treat a public function with no in-repo callers as dead. This is a library; a grep inside it cannot see a single consumer. Pin it with a test instead -- see `test/config/consumer_contract_test.exs`.

## Intent-provided tooling

### Skills (auto-loaded every Claude Code session)

- `/in-session` — session bootstrap. Run after `/compact`, context reset, or session start. Auto-loads language-appropriate skills.
- `/in-essentials`, `/in-standards` — universal workflow rules.
- `/in-review`, `/in-verify`, `/in-debug`, `/in-finish` — review / verify / debug / wrap-up flows.
- Language-specific — `/in-[[LANG]]-essentials` (and others) loaded on demand by `/in-session`.

Full list: `intent claude skills list`.

### Subagents (invoke via `Task()`)

- `intent` — Intent methodology.
- `socrates` — CTO Review Mode (architectural / strategic dialog).
- `diogenes` — Elixir Test Architect (spec generation / validation).
- `critic-<lang>` — rule-library critic: `critic-elixir`, `critic-rust`, `critic-swift`, `critic-lua`, `critic-shell`.

Socrates and Diogenes are disjoint; see `intent/docs/working-with-llms.md` at the Intent install for the FAQ.

### Rule library

Coding rules live in `intent/plugins/claude/rules/` at the Intent install and are enforced by the `critic-<lang>` family. Per-project overrides via `.intent_critic.yml` at this project's root.

Key commands:

```bash
intent claude rules list
intent claude rules show <id>
intent claude rules validate
```

### Extensions

User extensions at `~/.intent/ext/<name>/` contribute subagents, skills, or rule packs without forking Intent. `intent ext list | show | validate | new`.

## Session Hooks

`.claude/settings.json` wires:

- `UserPromptSubmit` (strict) — blocks the first prompt until `/in-session` runs in the conversation.
- `Stop` — reminds to run `/in-finish` on wrap.
- `PostToolUse` — optional advisory critic (off by default; opt-in via `.intent_critic.yml`).

Hooks are applied to this project by `intent claude upgrade --apply`. Never edit `.claude/settings.json` hook stanzas directly — re-apply the template instead.

## Critics and pre-commit

`.git/hooks/pre-commit` runs `bin/intent_critic [[LANG]]` on staged files. Severity threshold and disabled rules configured via `.intent_critic.yml` at project root:

```yaml
severity_min: warning # critical | warning | recommendation | style
disabled: # rule IDs to suppress (include reason comments)
  - IN-EX-CODE-007 # reason: moduledoc noise not valued here
```

Full contract: `intent/docs/critics.md` at the Intent install.

## NEVER DO

- Never edit `AGENTS.md` directly — it is auto-generated by `intent agents sync`.
- Never manually edit `.claude/settings.json` hook stanzas — re-apply via `intent claude upgrade --apply`.
- Never bypass `.git/hooks/pre-commit` with `--no-verify` on shared branches without an explicit justification in the commit message.
- Never create steel thread or work package directories manually — use `intent st new` and `intent wp new`.
- Never manually edit `status:` fields in info.md frontmatter — use `intent st start | done | cancel` and `intent wp start | done`.
- Never use leading zeros for ST or WP specifiers (`ST0035` or `35`, never `0035`) — leading zeros parse as octal in bash.
- Never manually wrap lines in markdown files — let the renderer handle it.
- Never delete `Arca.Config.register_change_callback/2`. It has no callers anywhere, and arca_cli probes its existence with `function_exported?/2` as a liveness check — remove it and every `save_settings` downstream silently stops persisting. A call-graph search cannot find that consumer; `consumer_contract_test.exs` pins it.

## See also

- `AGENTS.md` — project navigation (auto-generated)
- `CLAUDE.md` — Claude-specific scaffold
- `intent/docs/working-with-llms.md` — LLM workflow narrative (at Intent install)
- `intent/docs/rules.md` — rule authoring guide (at Intent install)
- `intent/docs/critics.md` — Critic contract (at Intent install)
