# Arca Config

Arca Config is a simple file-based configuration utility for Elixir projects. It provides an easy way to store and retrieve configuration values in a JSON file, with support for nested properties using dot notation.

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `arca_config` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:arca_config, "~> 0.3.0"}
  ]
end
```

## Setup

**IMPORTANT**: Starting from this version, Arca.Config requires OTP start phases for proper initialization.

### 1. Add dependency to mix.exs

See [Installation](#installation) above.

### 2. Configure start phases in mix.exs

```elixir
def application do
  [
    extra_applications: [:logger],
    start_phases: [load_config: []]
  ]
end
```

### 3. Set config domain and implement start phase in your Application module

```elixir
defmodule MyApp.Application do
  use Application

  @impl true
  def start(_type, _args) do
    # REQUIRED: Set the config domain before starting supervision tree
    Application.put_env(:arca_config, :config_domain, :my_app)

    children = [
      # Your supervisors and workers here
    ]

    opts = [strategy: :one_for_one, name: MyApp.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @impl true
  def start_phase(:load_config, _start_type, _phase_args) do
    # REQUIRED: Load configuration during start phase
    Arca.Config.load_config_phase()
  end
end
```

## Usage

### As a Library

```elixir
# Read a configuration value
{:ok, value} = Arca.Config.get("database.host")

# Read a configuration value (raises on error)
value = Arca.Config.get!("database.host")

# Write a configuration value
{:ok, _} = Arca.Config.put("database.host", "localhost")

# Write a configuration value (raises on error)
Arca.Config.put!("database.host", "localhost")

# Reload configuration from disk
{:ok, config} = Arca.Config.reload()
```

### As a CLI

Arca Config can also be used as a command-line tool, through a mix task:

```bash
# Get a configuration value
mix arca.config get database.host

# Set a configuration value
mix arca.config set database.host localhost

# List all configuration values
mix arca.config list

# Watch a key and print each change until interrupted
mix arca.config watch database.host
```

`bin/ac cli` runs the same task through this repository's dev launcher; it is a convenience for working *on* arca_config, not part of the library's interface. It replaced `./scripts/cli`, which also claimed to load `config/.env` first -- it did, redundantly, because `config/dotenv.exs` already does it during config evaluation (see Environment Variables below). The launcher does not repeat it.

A value is stored as what it denotes: `true` and `false` become booleans, digits become numbers, and a JSON object or array is decoded. Anything else is stored as the string you typed. There is no longer an escript build target -- it was undocumented and unbuilt, and the mix task is the path that was actually in use.

## Configuration

Arca Config derives its configuration location from the config domain. Set the domain explicitly in your application's `start/2`; it is not guessed:

```elixir
Application.put_env(:arca_config, :config_domain, :my_app)
```

With a domain of `:my_app`, the configuration file is `./.my_app/config.json` — relative to the working directory, not the home directory — unless you point it somewhere else.

**One location is resolved, and it does not depend on which files exist.** Asking for the config file returns the configured location whether or not anything is there yet, so a write creates the file you asked for rather than being redirected the moment the configured one is missing.

### Custom Configuration Locations

A directory and a filename are resolved independently, each from the first tier that answers:

| Priority   | Directory                                          | Filename                                |
| ---------- | -------------------------------------------------- | --------------------------------------- |
| 1 highest  | `MY_APP_CONFIG_PATH` (from your domain)            | `MY_APP_CONFIG_FILE`                    |
| 2          | `ARCA_CONFIG_PATH`                                 | `ARCA_CONFIG_FILE`                      |
| 3          | `config :arca_config, config_path: "/custom/path"` | `config :arca_config, config_file: ...` |
| 4 lowest   | `.my_app/` in the working directory                | `config.json`                           |

**The domain-specific variables win over the generic ones.** Earlier versions of this README claimed the opposite. If you are isolating configuration in a test suite, set the domain-specific pair: setting `ARCA_CONFIG_PATH` while your application defines a domain has no effect, and fails silently.

The result is always an absolute path, so a trailing slash in an environment variable is not preserved.

### Environment Variables (.env file)

**This is not a library feature.** `config/dotenv.exs` belongs to this repository's own dev and test setup: it is imported by *this project's* `config/config.exs` and is never evaluated in a project that depends on `arca_config`. Adding a `config/.env` to your own project does nothing unless you wire up the equivalent yourself.

For the record, since the file used to be advertised here as something it is not: it reads `config/.env` during config evaluation and treats each line as a **default**. A variable already exported by your shell, or set by CI, wins. It previously overwrote them unconditionally, which meant a variable you exported before `mix test` was replaced before a single test ran, and a fresh clone with no `.env` resolved a different config location than a working tree with one.

## Development

This repository uses [devbin](https://github.com/matthewsinclair/devbin) as its dev launcher. `bin/ac` is the short alias for `bin/arca_config`; `bin/ac help` lists everything it offers and `bin/ac help --why` also says what it does not offer, and why.

```bash
# Run the gates -- ExUnit at CI's strictness, then credo
bin/ac test all

# Read-only checks: compile, format, deps, critic
bin/ac check all

# IEx with the project loaded
bin/ac iex

# Use the CLI, plain or inside IEx
bin/ac cli
bin/ac cli --iex

# API documentation, via ExDoc
bin/ac docs exdoc
```

Every gate seals its verdict to a file under `tmp/`: an empty `.errors` file is a completed green run, so a gate that examined nothing cannot report success. The commands above replaced `./scripts/{test,iex,cli}`, which are gone.

## License

MIT
