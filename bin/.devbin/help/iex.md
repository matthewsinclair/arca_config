arca_config iex -- IEx with the project compiled, loaded and started.

    bin/ac iex

Runs `iex -S mix`. The application starts, so Arca.Config is supervised and running and its whole API is at the prompt.

    iex> Arca.Config.get("some.key")
    iex> Arca.Config.put("some.key", "value")
    iex> Arca.Config.get_config_location()
    iex> Arca.Config.CLI.main(["list"])

THIS is what replaced the retired scripts/iex -- not `cli --iex`, which is what the WP-02 inventory first recorded and which does nothing at all (Devbin issue 0009).

scripts/iex ran `iex -S mix Arca.Config`, which is this command plus running the CLI task at startup. `mix Arca.Config` and `mix arca.config` resolve to the same module, `Mix.Tasks.Arca.Config`, and the app starts either way, so nothing about the running system differs. What is gone is a usage banner printed before the prompt appears, and the ability to pass CLI arguments through to that startup invocation. From inside the session `Arca.Config.CLI.main(["list"])` does the second one better, so the loss is recorded rather than restored.

It also dropped a dead `ARCA_CONFIG_PATH=.arca`, which was shadowed by the tier-1 `ARCA_CONFIG_CONFIG_PATH` that config/.env sets -- and which would therefore have fired for the first time on a fresh clone, writing an unignored .arca/ into the checkout. The full reasoning is the WP-02 inventory in the Devbin repo.

The interactive Arca Config CLI is not this: `bin/ac iex` is an Elixir shell. `repl` is `enabled: false` here because this project's task has no repl subcommand -- arca_cli is where that lives.
