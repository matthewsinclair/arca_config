defmodule Arca.Config do
  @moduledoc """
  Arca.Config provides a simple file-based configuration utility for Elixir projects.

  It allows reading from and writing to a JSON configuration file, with support for
  nested properties using dot notation.

  ## Change notifications

  Three channels report configuration changes, and each fires exactly once per
  change event on every path below. This table is the contract; the individual
  functions refer back to it rather than restating it.

  | Channel                                             | put / delete             | reload            | external edit detected   | location switch   |
  | ----------------------------------------------------- | -------------------------- | ------------------- | -------------------------- | ------------------- |
  | `subscribe/1` -- `{:config_updated, path, value}`    | when that path's value changed | same            | same                     | same              |
  | `register_change_callback/2` -- whole config map     | once                     | once              | once                     | once              |
  | `add_callback/1` -- no arguments                     | once                     | once              | once                     | once              |

  Two rules make this coherent:

  - **A write that changes nothing is not a change event.** This applies to
    writes the application makes and to writes it finds on disk, which is why
    the application's own writes never arrive back as external changes -- there
    is no suppression window for a genuine external edit to be lost in. It is
    also why a callback that writes a derived value settles instead of
    re-triggering itself forever.
  - **An explicit `reload/0` or `switch_config_location/1` announces either
    way**, even when the values come back identical, because the caller asked
    for it and may be holding derived state to refresh. Per-key subscribers are
    still told only about paths whose value actually changed.

  Callbacks run outside the configuration server's own process, so a callback
  may read or write configuration without deadlocking against the change that
  triggered it. They are therefore asynchronous: a callback may not have run by
  the time `put/2` returns. Per-key subscriber messages are sent before the
  call returns.

  ## OTP Start Phase Integration

  **IMPORTANT**: Starting from this version, Arca.Config uses OTP start phases for
  deterministic configuration loading. Parent applications MUST:

  1. Set the config domain in their `Application.start/2` callback:
     ```elixir
     def start(_type, _args) do
       Application.put_env(:arca_config, :config_domain, :my_app)
       # ... start supervisor tree
     end
     ```

  2. Implement the `:load_config` start phase:
     ```elixir
     def start_phase(:load_config, _start_type, _phase_args) do
       Arca.Config.load_config_phase()
     end
     ```

  3. Define start phases in mix.exs:
     ```elixir
     def application do
       [
         extra_applications: [:logger],
         start_phases: [load_config: []]
       ]
     end
     ```

  ## Usage

  The configuration system supports both a railway-oriented programming style:

      iex> {:ok, _} = Arca.Config.put("test_key", "test_value")
      iex> Arca.Config.get("test_key")
      {:ok, "test_value"}

  And a Map-like interface via Arca.Config.Map:

      iex> {:ok, _} = Arca.Config.put("sample", "value")
      iex> config = Arca.Config.Map.new()
      iex> config["sample"]
      "value"

  ## Runtime Config Location Switching

  Arca.Config supports changing the configuration file location at runtime, which is
  particularly useful for testing scenarios where different tests need different configurations:

      # Switch to test configuration
      {:ok, previous_location} = Arca.Config.switch_config_location(
        path: "/tmp/test_config",
        file: "test.json"
      )

      # Your test code here...

      # Restore previous configuration
      Arca.Config.switch_config_location(previous_location)

  ### Example: Environment-based Configuration

      # Development config
      dev_config = %{
        "environment" => "development",
        "database" => %{"host" => "localhost", "port" => 5432},
        "debug" => true
      }

      # Test config
      test_config = %{
        "environment" => "test",
        "database" => %{"host" => "test-db", "port" => 5433},
        "debug" => false
      }

      # Switch between environments
      {:ok, _} = Arca.Config.switch_config_location(
        path: "config/dev",
        file: "config.json"
      )

      # In tests, switch to test config
      {:ok, original} = Arca.Config.switch_config_location(
        path: "config/test",
        file: "test.json"
      )

      # Run tests...

      # Restore original config
      Arca.Config.switch_config_location(original)

  The `switch_config_location/1` function handles:
  - Stopping the current FileWatcher
  - Clearing the configuration cache
  - Loading configuration from the new location
  - Restarting the FileWatcher on the new location
  - Notifying all registered callbacks
  """

  use Application

  alias Arca.Config.Cfg
  alias Arca.Config.CLI
  alias Arca.Config.Server
  alias Arca.Config.Supervisor, as: ConfigSupervisor
  alias Arca.Config.Value

  @doc """
  Handle Application functionality to start the Arca.Config subsystem.

  Starts the supervisor tree that manages the configuration system.
  Configuration loading is handled through OTP start phases.
  """
  @impl true
  def start(_type, _args) do
    # Start the supervisor - configuration will be loaded during start phase
    ConfigSupervisor.start_link([])
  end

  @doc """
  Loads configuration during the :load_config start phase.

  This function should be called by parent applications during their
  start phase implementation. It:

  1. Loads initial configuration from file
  2. Initializes the cache
  3. Starts file watching
  4. Applies environment variable overrides

  ## Returns
    - `:ok` if configuration was loaded successfully
    - `{:error, reason}` if there was an error
    
  ## Examples
      # In your application's start phase handler:
      def start_phase(:load_config, _start_type, _phase_args) do
        Arca.Config.load_config_phase()
      end
  """
  @spec load_config_phase() :: :ok | {:error, term()}
  def load_config_phase do
    load_result = Server.load_config()

    # File watching starts either way: a config that failed to load is exactly
    # the one most likely to be corrected on disk a moment later.
    Arca.Config.FileWatcher.start_watching()

    phase_result(load_result, apply_env_overrides())
  end

  # Both halves of the phase are reported. A load failure dominates when both
  # fail: overrides applied on top of a config that never loaded are a
  # consequence of it, not an independent fault.
  defp phase_result({:ok, _config}, :ok), do: :ok
  defp phase_result({:ok, _config}, {:error, _reason} = error), do: error
  defp phase_result({:error, reason}, _override_result), do: {:error, reason}

  defp apply_env_overrides do
    # Get the prefix for environment variables
    env_prefix = Arca.Config.Cfg.env_var_prefix()
    override_prefix = "#{env_prefix}_CONFIG_OVERRIDE_"

    # Get all environment variables with the override prefix
    System.get_env()
    |> Enum.filter(fn {key, _value} -> String.starts_with?(key, override_prefix) end)
    |> Enum.map(&apply_env_override(&1, override_prefix))
    |> Enum.reject(&(&1 == :ok))
    |> collect_override_failures()
  end

  # Apply one override, reporting `{key_path, reason}` on failure so every
  # failure reaches the caller together instead of being dropped one at a time.
  defp apply_env_override({env_var, value}, override_prefix) do
    key_path =
      env_var
      |> String.replace_prefix(override_prefix, "")
      |> String.downcase()
      |> String.replace("_", ".")

    case put(key_path, Value.from_string(value)) do
      {:ok, _value} -> :ok
      {:error, reason} -> {key_path, reason}
    end
  end

  defp collect_override_failures([]), do: :ok
  defp collect_override_failures(failures), do: {:error, {:env_overrides_failed, failures}}

  @doc """
  Gets a configuration value.

  ## Parameters
    - `key`: A string with dot notation, atom, or list of keys

  ## Returns
    - `{:ok, value}` if the key exists
    - `{:error, reason}` if the key doesn't exist or another error occurs

  ## Examples
      iex> {:ok, _} = Arca.Config.put("app.name", "MyApp")
      iex> Arca.Config.get("app.name")
      {:ok, "MyApp"}
  """
  @spec get(String.t() | atom() | list()) :: {:ok, any()} | {:error, term()}
  def get(key), do: Server.get(key)

  @doc """
  Gets a configuration value or raises an error if not found.

  ## Parameters
    - `key`: A string with dot notation, atom, or list of keys

  ## Returns
    - The configuration value if the key exists

  ## Raises
    - `RuntimeError` if the key doesn't exist or another error occurs

  ## Examples
      iex> Arca.Config.put!("app.name", "MyApp")
      "MyApp"
      iex> Arca.Config.get!("app.name")
      "MyApp"
  """
  @spec get!(String.t() | atom() | list()) :: any() | no_return()
  def get!(key), do: Server.get!(key)

  @doc """
  Updates a configuration value.

  ## Parameters
    - `key`: A string with dot notation, atom, or list of keys
    - `value`: The new value to set

  ## Returns
    - `{:ok, value}` if the update was successful
    - `{:error, reason}` if an error occurred

  ## Examples
      iex> {:ok, value} = Arca.Config.put("database.host", "localhost")
      iex> value
      "localhost"
  """
  @spec put(String.t() | atom() | list(), any()) :: {:ok, any()} | {:error, term()}
  def put(key, value), do: Server.put(key, value)

  @doc """
  Updates a configuration value or raises an error if the operation fails.

  ## Parameters
    - `key`: A string with dot notation, atom, or list of keys
    - `value`: The new value to set

  ## Returns
    - The value if the update was successful

  ## Raises
    - `RuntimeError` if an error occurred

  ## Examples
      iex> Arca.Config.put!("database.host", "localhost")
      "localhost"
  """
  @spec put!(String.t() | atom() | list(), any()) :: any() | no_return()
  def put!(key, value), do: Server.put!(key, value)

  @doc """
  Removes a configuration value.

  ## Parameters
    - `key`: A string with dot notation, atom, or list of keys

  ## Returns
    - `{:ok, key}` if the key was removed
    - `{:error, reason}` if the key did not exist or persistence failed

  ## Examples
      iex> {:ok, _} = Arca.Config.put("app.transient", "gone soon")
      iex> {:ok, _} = Arca.Config.delete("app.transient")
      iex> {:error, _} = Arca.Config.get("app.transient")
  """
  @spec delete(String.t() | atom() | list()) :: {:ok, any()} | {:error, term()}
  def delete(key), do: Server.delete(key)

  @doc """
  Removes a configuration value or raises if the operation fails.

  ## Parameters
    - `key`: A string with dot notation, atom, or list of keys

  ## Returns
    - The key if it was removed

  ## Raises
    - `RuntimeError` if the key did not exist or persistence failed

  ## Examples
      iex> Arca.Config.put!("app.transient", "gone soon")
      "gone soon"
      iex> {:ok, _} = Arca.Config.delete("app.transient")
  """
  @spec delete!(String.t() | atom() | list()) :: any() | no_return()
  def delete!(key), do: Server.delete!(key)

  @doc """
  Reports which configuration file is in use and which tier resolved it.

  The counterpart to `switch_config_location/1`: that one moves the location,
  this one tells you where it currently is and why. Path and filename resolve
  independently through the same four tiers, so each carries its own source --
  `:env_domain`, `:env_generic`, `:app_config`, or `:default`.

  Reads the environment directly rather than going through the server, so it
  still answers when the server is down -- which is exactly when the question
  gets asked.

  ## Returns
    - `{:ok, location}` with `:path`, `:file`, `:config_file`, and a `:source`
      map keyed by `:path` and `:file`

  ## Examples
      iex> {:ok, location} = Arca.Config.get_config_location()
      iex> is_binary(location.config_file)
      true
  """
  @spec get_config_location() ::
          {:ok,
           %{
             path: String.t(),
             file: String.t(),
             config_file: String.t(),
             source: %{path: atom(), file: atom()}
           }}
  def get_config_location, do: Cfg.config_location()

  @doc """
  Subscribes to changes to a specific configuration key.

  When the value at this key changes, a message of the format
  `{:config_updated, key_path, new_value}` will be sent to the caller.

  Delivered on every path that changes the value at this key: `put/2`,
  `delete/1`, `reload/0`, an externally detected edit, and a location switch --
  including when the value changed because an ancestor was replaced. A path
  whose value did not change is not reported. See "Change notifications" in the
  module documentation for the full matrix.

  ## Parameters
    - `key`: A string with dot notation, atom, or list of keys

  ## Returns
    - `{:ok, :subscribed}` if the subscription was successful

  ## Examples
      iex> Registry.start_link(keys: :duplicate, name: Arca.Config.Registry)
      iex> Arca.Config.subscribe("test_key")
      {:ok, :subscribed}
  """
  @spec subscribe(String.t() | atom() | list()) :: {:ok, :subscribed}
  def subscribe(key), do: Server.subscribe(key)

  @doc """
  Unsubscribes from changes to a specific configuration key.

  ## Parameters
    - `key`: A string with dot notation, atom, or list of keys

  ## Returns
    - `{:ok, :unsubscribed}` if the unsubscription was successful

  ## Examples
      iex> Registry.start_link(keys: :duplicate, name: Arca.Config.Registry)
      iex> Arca.Config.unsubscribe("test_key")
      {:ok, :unsubscribed}
  """
  @spec unsubscribe(String.t() | atom() | list()) :: {:ok, :unsubscribed}
  def unsubscribe(key), do: Server.unsubscribe(key)

  @doc """
  Registers a callback function to be called when the configuration changes.

  The callback receives the whole configuration map and fires once per change
  event on every path -- `put/2`, `delete/1`, `reload/0`, an externally detected
  edit, and a location switch -- not only on external edits. See "Change
  notifications" in the module documentation for the full matrix.

  The callback runs outside the configuration server's process, so it may read
  or write configuration itself. A callback that writes a derived value settles,
  because a write that changes nothing raises no further event.

  ## Parameters
    - `callback_id`: A unique identifier for the callback (used for unregistering)
    - `callback_fn`: A function that takes the entire config map as its only parameter

  ## Returns
    - `{:ok, :registered}` if the registration was successful

  ## Examples
      iex> Registry.start_link(keys: :duplicate, name: Arca.Config.CallbackRegistry)
      iex> callback_fn = fn config -> IO.puts("Config changed: \#{inspect(config)}") end
      iex> Arca.Config.register_change_callback(:my_callback, callback_fn)
      {:ok, :registered}
  """
  @spec register_change_callback(term(), (map() -> any())) :: {:ok, :registered}
  def register_change_callback(callback_id, callback_fn),
    do: Server.register_change_callback(callback_id, callback_fn)

  @doc """
  Unregisters a previously registered callback function.

  ## Parameters
    - `callback_id`: The identifier of the callback to unregister

  ## Returns
    - `{:ok, :unregistered}` if the unregistration was successful

  ## Examples
      iex> Registry.start_link(keys: :duplicate, name: Arca.Config.CallbackRegistry)
      iex> Arca.Config.unregister_change_callback(:my_callback)
      {:ok, :unregistered}
  """
  @spec unregister_change_callback(term()) :: {:ok, :unregistered}
  def unregister_change_callback(callback_id), do: Server.unregister_change_callback(callback_id)

  @doc """
  Adds a callback function to be called whenever the configuration changes.
  This callback does not receive any arguments, unlike `register_change_callback/2`.

  Fires once per change event on every path: `put/2`, `delete/1`, `reload/0`, an
  externally detected edit, and a location switch. It previously fired twice for
  a single externally detected change. See "Change notifications" in the module
  documentation for the full matrix.

  ## Parameters
    - `callback_fn`: A 0-arity function to execute when config changes

  ## Returns
    - `{:ok, reference}` if the registration was successful, where reference is used to remove the callback

  ## Examples
      iex> callback_fn = fn -> IO.puts("Config changed!") end
      iex> {:ok, _ref} = Arca.Config.add_callback(callback_fn)
  """
  @spec add_callback(function()) :: {:ok, reference()}
  def add_callback(callback_fn) when is_function(callback_fn, 0),
    do: Server.add_callback(callback_fn)

  @doc """
  Removes a previously registered callback function.

  ## Parameters
    - `callback_ref`: The reference returned by `add_callback/1`

  ## Returns
    - `{:ok, :removed}` if the callback was successfully removed
    - `{:error, :not_found}` if the callback wasn't registered

  ## Examples
      iex> callback_fn = fn -> IO.puts("Config changed!") end
      iex> {:ok, ref} = Arca.Config.add_callback(callback_fn)
      iex> Arca.Config.remove_callback(ref)
      {:ok, :removed}
  """
  @spec remove_callback(reference()) :: {:ok, :removed} | {:error, :not_found}
  def remove_callback(callback_ref), do: Server.remove_callback(callback_ref)

  @doc """
  Manually triggers notification of all registered callbacks.
  This can be useful when you want to force notification after a series of changes.

  ## Returns
    - `{:ok, :notified}` after all callbacks have been executed

  ## Examples
      iex> Arca.Config.notify_callbacks()
      {:ok, :notified}
  """
  @spec notify_callbacks() :: {:ok, :notified}
  def notify_callbacks, do: Server.notify_callbacks()

  @doc """
  Switches the configuration file location at runtime.

  This function allows you to change where Arca.Config reads and writes
  configuration data. It performs the following operations:

  1. Stops the current FileWatcher
  2. Updates environment variables with new location
  3. Clears the configuration cache
  4. Loads configuration from the new location
  5. Restarts the FileWatcher on the new location
  6. Notifies all callbacks of the change

  ## Parameters
    - `opts`: Keyword list with optional `:path` and `:file` keys
      - `:path` - The new configuration directory path
      - `:file` - The new configuration filename

  ## Returns
    - `{:ok, previous_location}` with the previous path and file settings
    - `{:error, reason}` if an error occurred

  The target location must already hold a config file: switching to a location
  that has none returns an error and leaves the current location live.

  ## Examples
      iex> new_location = Path.join(System.tmp_dir!(), "arca_switch_doctest")
      iex> File.mkdir_p!(new_location)
      iex> File.write!(Path.join(new_location, "test.json"), ~s({"switched": true}))
      iex> {:ok, old_location} = Arca.Config.switch_config_location(
      ...>   path: new_location,
      ...>   file: "test.json"
      ...> )
      iex> Arca.Config.get("switched")
      {:ok, true}
      iex> # Restore previous location
      iex> {:ok, _restored} = Arca.Config.switch_config_location(old_location)
      iex> File.rm_rf(new_location)
  """
  @spec switch_config_location(keyword()) :: {:ok, keyword()} | {:error, term()}
  def switch_config_location(opts \\ []) do
    Server.switch_config_location(opts)
  end

  @doc """
  Reloads the configuration from disk.

  ## Returns
    - `{:ok, config}` with the loaded configuration if successful
    - `{:error, reason}` if an error occurred

  ## Examples
      iex> app_specific_path_var = Arca.Config.Cfg.env_var_prefix() <> "_CONFIG_PATH"
      iex> app_specific_file_var = Arca.Config.Cfg.env_var_prefix() <> "_CONFIG_FILE"
      iex> System.put_env(app_specific_path_var, System.tmp_dir!())
      iex> System.put_env(app_specific_file_var, "doctest_config.json")
      iex> File.write!(Path.join(System.tmp_dir(), "doctest_config.json"), ~s({"app": {"name": "MyApp"}}))
      iex> {:ok, config} = Arca.Config.reload()
      iex> config["app"]["name"]
      "MyApp"
      iex> System.delete_env(app_specific_path_var)
      iex> System.delete_env(app_specific_file_var)
  """
  @spec reload() :: {:ok, map()} | {:error, term()}
  def reload, do: Server.reload()

  @doc """
  Entry point for the CLI.

  Delegates to `Arca.Config.CLI.main/1`, where the command specification, the
  handlers and the value conversion now live. This module kept all of it inline
  for a long time, which is how the facade came to be an Application callback,
  an API facade and a command-line program at once.
  """
  @spec main(list(String.t())) :: :ok
  def main(argv), do: CLI.main(argv)
end
