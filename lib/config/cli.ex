defmodule Arca.Config.CLI do
  @moduledoc """
  Command-line interface for Arca Config.

  Reached through `mix arca.config`, which is what `bin/acfg cli` invokes. It used
  to live inside `Arca.Config` alongside the Application callback and the API
  facade, and it dispatched twice: a hand-written `case` on `argv` intercepted
  `get`, `set`, `list` and `watch` before Optimus ever saw them, which left the
  whole Optimus subcommand specification and its four handlers unreachable
  (finding AF-11). There is now one dispatch, through the spec, so the help text
  and the behaviour cannot drift apart.

  Ruling R3 chose extract over delete. The escript target is gone from `mix.exs`
  -- it was undocumented, unbuilt in CI, and not invoked anywhere in the fleet --
  while the mix task, which is the documented path, stays.
  """

  alias Arca.Config.Error
  alias Arca.Config.Server
  alias Arca.Config.Value

  @doc """
  Entry point for the CLI.

  Parses `argv` against the command specification and runs the command.
  """
  @spec main(list(String.t())) :: :ok
  def main(argv) do
    cli_spec()
    |> Optimus.parse!(argv)
    |> process_command()
  end

  defp cli_spec do
    Optimus.new!(
      name: Application.get_env(:arca_config, :name, "arca_config"),
      description:
        Application.get_env(
          :arca_config,
          :description,
          "A simple file-based configurator for Elixir apps"
        ),
      # From the built application, so there is one version string in the
      # project rather than a copy in config.exs and a stale default here.
      version: to_string(Application.spec(:arca_config, :vsn)),
      author: Application.get_env(:arca_config, :author, "Arca"),
      about: Application.get_env(:arca_config, :about, "Arca Config CLI"),
      allow_unknown_args: true,
      parse_double_dash: true,
      subcommands: [
        get: [
          name: "get",
          about: "Get a configuration value",
          args: [
            key: [
              value_name: "KEY",
              help: "The configuration key to get (eg 'database.host')",
              required: true
            ]
          ]
        ],
        set: [
          name: "set",
          about: "Set a configuration value",
          # An unquoted multi-word value arrives as trailing unknown args, and
          # the dispatch this replaces joined them with spaces. Keeping that
          # means `set greeting hello there` still does what it always did.
          allow_unknown_args: true,
          args: [
            key: [
              value_name: "KEY",
              help: "The configuration key to set (eg 'database.host')",
              required: true
            ],
            value: [
              value_name: "VALUE",
              help: "The value to set",
              required: true
            ]
          ]
        ],
        list: [
          name: "list",
          about: "List all configuration values"
        ],
        watch: [
          name: "watch",
          about: "Watch for changes to a configuration key",
          args: [
            key: [
              value_name: "KEY",
              help: "The configuration key to watch (eg 'database.host')",
              required: true
            ]
          ]
        ]
      ]
    )
  end

  defp process_command({[:list], _parse_result}) do
    handle_list()
  end

  defp process_command({[:get], %{args: %{key: key}}}) do
    handle_get(key)
  end

  defp process_command({[:set], %{args: %{key: key, value: value}, unknown: rest}}) do
    handle_set(key, Enum.join([value | rest], " "))
  end

  defp process_command({[:watch], %{args: %{key: key}}}) do
    handle_watch(key)
  end

  defp process_command(_) do
    IO.puts("Invalid command. Use --help for usage information.")
    :ok
  end

  defp handle_get(key) do
    case Arca.Config.get(key) do
      {:ok, value} -> print_value(value)
      {:error, reason} -> IO.puts("Error: #{Error.message(reason)}")
    end
  end

  defp handle_set(key, value) do
    converted = Value.from_string(value)

    case Arca.Config.put(key, converted) do
      {:ok, _} -> IO.puts("Successfully set '#{key}' to '#{inspect(converted)}'")
      {:error, reason} -> IO.puts("Error: #{Error.message(reason)}")
    end
  end

  defp handle_list do
    case Server.reload() do
      {:ok, config} -> IO.puts(Jason.encode!(config, pretty: true))
      {:error, reason} -> IO.puts("Error: #{Error.message(reason)}")
    end
  end

  defp handle_watch(key) do
    Arca.Config.subscribe(key)

    IO.puts("Watching #{key}. Current value:")
    handle_get(key)
    IO.puts("\nWaiting for changes... (Press Ctrl+C to exit)")

    watch_loop(key)
  end

  defp watch_loop(key) do
    receive do
      {:config_updated, key_path, value} ->
        IO.puts("\nConfig updated: #{Enum.join(key_path, ".")}")
        print_value(value)

        watch_loop(key)
    end
  end

  # One printer for both the get path and the watch path. A string prints as
  # itself, so `get database.host` still answers `localhost` rather than
  # `"localhost"`; everything else prints as JSON. The two paths used to print
  # differently, and neither could show a list: `IO.puts/1` treats one as
  # chardata, so a JSON array read back through `get` printed control
  # characters.
  defp print_value(value) when is_binary(value), do: IO.puts(value)
  defp print_value(value), do: IO.puts(Jason.encode!(value, pretty: true))
end
