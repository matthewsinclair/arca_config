# Changelog

## 0.3.0 -- unreleased

A breaking release. Every change below came out of ST0002, an audit of the whole library followed by remediation in five work packages. The theme is that the surface used to lie in three directions -- to callers, to subscribers, and to readers -- and now does not.

Version 0.x per ruling R5: the location model is settled but young, so this stays below 1.0.

### If you are upgrading, read this first

**One change needs action in your code.** If you match on error reasons, they have changed shape -- see *Errors* below. Everything else either fails loudly where it used to fail silently, or is additive.

**The most likely thing to bite you** is that operations which previously could not fail now can. That is the point of the release: they always could, and used to report success anyway.

### Errors -- one shape, and you match on it

Every public failure is now:

```elixir
{:error, {:config, reason, detail}}
```

`reason` is a machine-matchable atom (`:not_found`, `:load_failed`, `:write_failed`) that will not be reworded. `detail` is the key path for key-scoped failures, and the underlying cause otherwise -- a posix atom, or a descriptive string for a parse failure.

```elixir
# Before                              # After
{:error, "Key not found"}             {:error, {:config, :not_found, ["database", "host"]}}
{:error, "'database.host' not found"} {:error, {:config, :not_found, ["database", "host"]}}
{:error, "No such property: \"id\""}  {:error, {:config, :not_found, ["id"]}}
{:error, "Failed to load config file: enoent"}
                                      {:error, {:config, :load_failed, :enoent}}
{:error, :eacces}                     {:error, {:config, :write_failed, :eacces}}
```

There used to be four ways of saying "no such key", which meant the only way to classify one was to match on English prose. Nothing was thrown away in the move: the text that used to *be* the error is now the `detail`, so a parse failure still reports its position and token. `Arca.Config.Error.message/1` renders any reason for a person.

The error also now names the key **you asked for**. It previously reported whichever suffix the lookup stopped on, so `get("database.host.deeper")` said `"Key not found"` with no way to tell which part was missing.

Two shapes deliberately did **not** change, and both are documented in `Arca.Config.Error`:

- `Arca.Config.Cache` keeps `{:error, :not_found}` / `{:error, :cache_unavailable}`. Its "not found" means *not cached*, which is not the claim *no such key*.
- `Server.remove_callback/1` keeps `{:error, :not_found}`. A callback reference is not a configuration key.

### Writes now tell you the truth

`put/2`, `delete/1`, `put!/2` and `delete!/1` **can now fail**. A `put` against an unwritable file used to log `:eacces`, return `{:ok, value}`, advance the cache, and serve the phantom value from memory for the rest of the session. It now returns `{:error, {:config, :write_failed, :eacces}}` and advances nothing -- a subsequent `get` reflects what is on disk.

A failed environment-override application is reported from `load_config_phase/0` as `{:error, {:env_overrides_failed, failures}}` instead of being dropped.

A failed load surfaces as a load error to the caller. It used to mark the config loaded-and-empty, so every key thereafter reported "not found" and the real cause was lost.

`switch_config_location/1` to a location with no config file now returns an error and **leaves the previous location live** -- config, cache and environment variables all intact. It used to succeed with an empty config. Reading a missing file as an empty one now survives only on the documented first-run bootstrap path (ruling R4).

### Configuration location

**The domain is no longer guessed.** `config_domain/0` is `Application.get_env(:arca_config, :config_domain)` or `:arca_config`. It used to walk the caller chain and then take the first non-system started application, which returned whichever application happened to be running -- a probe resolved it to `:elixir_uuid`, a dependency; the test suite resolved it to `:ex_unit`. **If you never set `:config_domain` and relied on detection, set it explicitly now.**

**`config_file/0` no longer falls back.** It returns the configured location whether or not a file is there. It used to switch to a working-directory default whenever the configured file was missing, so a write to a configured-but-absent file landed somewhere the caller never asked for.

**The precedence documentation was backwards** and is corrected. The domain-specific variable (`MY_APP_CONFIG_PATH`) beats the generic one (`ARCA_CONFIG_PATH`). The code always did this; the README said the opposite, which is why at least one downstream project's test isolation set `ARCA_CONFIG_PATH` across nine files and never once took effect.

**`config_pathname/0` returns an expanded absolute path** from every tier. Environment-variable values used to be returned verbatim.

### Change notifications

One matrix, documented on `Arca.Config` and on each of `subscribe/1`, `register_change_callback/2` and `add_callback/1`. Three channels x five mutation paths (put, delete, reload, external edit detected, location switch), each firing exactly once. Previously the three channels fired on disjoint, undocumented subsets: per-key subscribers never fired for the external changes the file watcher exists to catch, and 0-arity callbacks fired twice per detected change.

Two rules make it coherent:

- **A write that changes nothing raises no event.** This is what stops your own writes arriving back as external changes -- so the old post-write suppression window is gone entirely, and no genuine external edit can be lost inside it. It also stops a callback that writes a derived value from re-triggering itself forever.
- **An explicit `reload/0` or `switch_config_location/1` announces either way**, because the caller asked for it and may hold derived state.

**Callbacks now run outside the server process**, so a callback may read or write configuration without deadlocking against the change that triggered it. They are therefore asynchronous: a callback may not have run by the time `put/2` returns. Per-key subscriber messages are still sent before the call returns.

The file watcher **survives a malformed configuration file**: it logs, keeps the last good config, and keeps watching. One hand-edit with a stray brace used to crash it into permanent, silent dormancy.

### Added

- `Arca.Config.delete/1` and `delete!/1` on the facade. They existed on the server and were missing from the facade.
- `Arca.Config.get_config_location/0`, answering which file is in use and **which tier resolved it** -- `:env_domain`, `:env_generic`, `:app_config` or `:default`, reported separately for the directory and the filename. This is the answer to "why is it reading *that* file", which previously took an afternoon.
- `Arca.Config.Error`, which owns the error shape and renders it.
- `Arca.Config.Value.from_string/1`, the string coercion used by both the CLI and the environment-override path.
- `Arca.Config.CLI`, holding the command-line interface that used to live in the facade module.

### Changed

- `Arca.Config.Cfg.get/1`, `get!/1`, `put/2` and `put!/2` now delegate to `Arca.Config.Server`. They were a second implementation that read from disk on every call, wrote straight back to disk, and told nobody -- so the running server's memory and the cache stayed stale until the watcher noticed. **Consequence:** they read server state, so moving the location behind the server's back and expecting reads to follow no longer works. Use `switch_config_location/1`, or `reload/0`.
- `Access.pop/2` and `get_and_update/3`'s `:pop` on `Arca.Config.Map` **actually delete** now. They returned the value and left the key in place.

### Removed

- **The escript build target.** It was undocumented, unbuilt in CI, and invoked nowhere. `mix arca.config` -- the path that was actually in use -- replaces it, with the same commands.
- Two test-only GenServer messages that shipped in production modules: `{:reset_for_test, config}` (which had no callers at all) and `{:reset_to_dormant, pid}` (a second, worse copy of `FileWatcher.stop_watching/0`).
- Four `.arca_config/` artifacts and three debug scripts that had been committed to version control.

### Notes for arca_cli specifically

`Arca.Cli.setting_error/2` classifies a missing setting with three clauses: a bare `:not_found`, a binary containing "not found", and a generic fallback. The canonical tuple matches neither accepting clause, so until arca_cli gains one, a missing setting renders as `cannot read setting X: {:config, :not_found, ["x"]}` -- degraded message text on an error path, never a crash, with every success path untouched. The clause it needs, placed **above** the `is_binary` clause:

```elixir
defp setting_error(id_str, {:config, :not_found, _key_path}), do: "setting not found: #{id_str}"
```

One arca_cli test asserts the end-to-end rendering of that message (`test/arca_cli/error_format_test.exs`, "failure: a setting that does not exist") and will fail until the clause lands.

## 0.2.0

Prior releases predate this changelog.
