arca_config cli [args...] -- one-shot Arca Config: run a single command and exit.

    bin/ac cli list                     list every configuration value
    bin/ac cli get <key>                read one
    bin/ac cli set <key> <value>        write one
    bin/ac cli watch <key>              watch a key for changes
    bin/ac cli --help                   the CLI's own help, not this topic

It runs `mix arca.config`, and NOT the builtin's `mix <name>.cli`. This project's task is declared as `arca.config` (via `mix_tasks:` in mix.exs, implemented at lib/mix/tasks/arca_config.ex as `Mix.Tasks.Arca.Config`), so the catalogue's `mix arca_config.cli` would not resolve at all. That one difference is the entire reason `commands.cli.run` is declared in bin/.devbin/config.yaml rather than left to the built-in handler.

Every argument passes through verbatim, so the CLI owns its whole flag surface: `bin/ac cli --help` reaches Arca Config's own help rather than this topic, and a value containing spaces survives because the dispatcher quotes properly where the retired launcher did not.

There is no `.env` preamble, deliberately. config/dotenv.exs is imported by config.exs and loads config/.env during mix configuration evaluation, on every dev and test invocation, as defaults rather than overrides and tolerating a missing file. The retired scripts/ launcher exported the same variables in shell beforehand; mix had been doing it correctly all along, and two of those three scripts did it in a form that failed outright on a fresh clone.

`--iex` does not work here even though help offers it. devbin advertises `--iex` because this project declares elixir, but the only command that reads it is the built-in `server`, which is `enabled: false` here -- so `bin/ac cli --iex` is accepted and silently changes nothing (Devbin issue 0009). For IEx with the project loaded, the command is `bin/ac iex`; see `bin/ac help iex`.

Folds the retired scripts/cli, which this replaces one-for-one.
