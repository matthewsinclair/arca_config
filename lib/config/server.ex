defmodule Arca.Config.Server do
  @moduledoc """
  GenServer that manages the configuration state.

  This server is responsible for:
  1. Loading configuration from files
  2. Maintaining in-memory state of configuration
  3. Coordinating cache updates
  4. Notifying subscribers of configuration changes
  5. Persisting configuration changes to disk
  """

  use GenServer

  alias Arca.Config.Cache
  alias Arca.Config.Cfg
  alias Arca.Config.Error

  # Client API

  @doc """
  Starts the configuration server.
  """
  def start_link(_opts) do
    GenServer.start_link(__MODULE__, nil, name: __MODULE__)
  end

  @doc """
  Gets a configuration value by key path.

  ## Parameters
    - `key`: A dot-separated string or atom path (e.g., "database.host" or [:database, :host])

  ## Returns
    - `{:ok, value}` if the key exists
    - `{:error, reason}` if the key doesn't exist or another error occurs
  """
  @spec get(String.t() | atom() | list()) :: {:ok, any()} | {:error, term()}
  def get(key) do
    key_path = normalize_key_path(key)
    normal_get(key_path)
  end

  # Standard get operation
  defp normal_get(key_path) do
    # Try to get from cache first. A miss and an unavailable cache lead to the
    # same next step -- ask the server -- but they are distinct answers at the
    # cache API, so the difference stays visible where it matters.
    case Cache.get(key_path) do
      {:ok, value} ->
        {:ok, value}

      {:error, _not_cached} ->
        # Not in cache, try to get from disk and update cache if found
        case GenServer.call(__MODULE__, {:get, key_path}) do
          {:ok, value} = result ->
            # Update cache with the value
            key_path |> Cache.put(value) |> report_cache_result()
            result

          error ->
            error
        end
    end
  end

  @doc """
  Gets a configuration value by key path or raises an error if not found.

  ## Parameters
    - `key`: A dot-separated string or atom path (e.g., "database.host" or [:database, :host])

  ## Returns
    - The configuration value if the key exists

  ## Raises
    - `RuntimeError` if the key doesn't exist or another error occurs
  """
  @spec get!(String.t() | atom() | list()) :: any() | no_return()
  def get!(key) do
    case get(key) do
      {:ok, value} ->
        value

      {:error, reason} ->
        raise RuntimeError, message: "Configuration error: #{Error.message(reason)}"
    end
  end

  @doc """
  Updates a configuration value.

  ## Parameters
    - `key`: A dot-separated string or atom path (e.g., "database.host" or [:database, :host])
    - `value`: The new value to set

  ## Returns
    - `{:ok, value}` if the update was successful
    - `{:error, reason}` if an error occurred
  """
  @spec put(String.t() | atom() | list(), any()) :: {:ok, any()} | {:error, term()}
  def put(key, value) do
    key_path = normalize_key_path(key)
    GenServer.call(__MODULE__, {:put, key_path, value})
  end

  @doc """
  Updates a configuration value or raises an error if the operation fails.

  ## Parameters
    - `key`: A dot-separated string or atom path (e.g., "database.host" or [:database, :host])
    - `value`: The new value to set

  ## Returns
    - The value if the update was successful

  ## Raises
    - `RuntimeError` if an error occurred
  """
  @spec put!(String.t() | atom() | list(), any()) :: any() | no_return()
  def put!(key, value) do
    case put(key, value) do
      {:ok, result} ->
        result

      {:error, reason} ->
        raise RuntimeError, message: "Configuration error: #{Error.message(reason)}"
    end
  end

  @doc """
  Deletes a configuration key and its value.

  ## Parameters
    - `key`: A dot-separated string or atom path (e.g., "database.host" or [:database, :host])

  ## Returns
    - `{:ok, :deleted}` if the deletion was successful
    - `{:error, reason}` if an error occurred
  """
  @spec delete(String.t() | atom() | list()) :: {:ok, :deleted} | {:error, term()}
  def delete(key) do
    key_path = normalize_key_path(key)
    GenServer.call(__MODULE__, {:delete, key_path})
  end

  @doc """
  Deletes a configuration key and its value or raises an error if the operation fails.

  ## Parameters
    - `key`: A dot-separated string or atom path (e.g., "database.host" or [:database, :host])

  ## Returns
    - `:deleted` if the deletion was successful

  ## Raises
    - `RuntimeError` if an error occurred
  """
  @spec delete!(String.t() | atom() | list()) :: :deleted | no_return()
  def delete!(key) do
    case delete(key) do
      {:ok, result} ->
        result

      {:error, reason} ->
        raise RuntimeError, message: "Configuration error: #{Error.message(reason)}"
    end
  end

  @doc """
  Reloads the configuration from disk.

  ## Returns
    - `{:ok, config}` with the loaded configuration if successful
    - `{:error, reason}` if an error occurred
  """
  @spec reload() :: {:ok, map()} | {:error, term()}
  def reload do
    GenServer.call(__MODULE__, :reload)
  end

  @doc """
  Reloads the configuration after a write to the file was detected.

  Identical to `reload/0` except in what it announces: a write raises a change
  event only when the configuration actually differs from the one already in
  memory. That is what stops the application's own writes from arriving back as
  external changes, without a suppression window for a real external edit to be
  lost in. An explicit `reload/0`, by contrast, announces either way, because
  the caller asked for it and may be holding derived state to refresh.

  ## Returns
    - `{:ok, config}` with the loaded configuration if successful
    - `{:error, reason}` if an error occurred
  """
  @spec reload_external() :: {:ok, map()} | {:error, term()}
  def reload_external do
    GenServer.call(__MODULE__, {:reload, :announce_if_changed})
  end

  @doc """
  Subscribes to changes to a specific configuration key.

  Delivers `{:config_updated, key_path, new_value}` on every path that changes
  the value at this key -- put, delete, reload, an externally detected edit, and
  a location switch -- including when it changed because an ancestor was
  replaced. A path whose value did not change is not reported. The full matrix
  is in the `Arca.Config` module documentation.

  ## Parameters
    - `key`: A dot-separated string or atom path (e.g., "database.host" or [:database, :host])

  ## Returns
    - `{:ok, :subscribed}` if the subscription was successful
  """
  @spec subscribe(String.t() | atom() | list()) :: {:ok, :subscribed}
  def subscribe(key) do
    key_path = normalize_key_path(key)
    Registry.register(Arca.Config.Registry, key_path, nil)
    {:ok, :subscribed}
  end

  @doc """
  Unsubscribes from changes to a specific configuration key.

  ## Parameters
    - `key`: A dot-separated string or atom path (e.g., "database.host" or [:database, :host])

  ## Returns
    - `{:ok, :unsubscribed}` if the unsubscription was successful
  """
  @spec unsubscribe(String.t() | atom() | list()) :: {:ok, :unsubscribed}
  def unsubscribe(key) do
    key_path = normalize_key_path(key)
    Registry.unregister(Arca.Config.Registry, key_path)
    {:ok, :unsubscribed}
  end

  @doc """
  Registers a callback function to be called when the configuration changes.

  Fires once per change event on every path -- put, delete, reload, an
  externally detected edit, and a location switch -- not only on external edits.
  The callback runs outside this server's process, so it may read or write
  configuration itself. The full matrix is in the `Arca.Config` module
  documentation.

  ## Parameters
    - `callback_id`: An identifier for the callback (used for unregistering)
    - `callback_fn`: A function that takes a map of the entire config as its argument

  ## Returns
    - `{:ok, :registered}` if the registration was successful
  """
  @spec register_change_callback(term(), (map() -> any())) :: {:ok, :registered}
  def register_change_callback(callback_id, callback_fn) when is_function(callback_fn, 1) do
    Registry.register(Arca.Config.CallbackRegistry, :config_change, {callback_id, callback_fn})
    {:ok, :registered}
  end

  @doc """
  Unregisters a previously registered callback function.

  ## Parameters
    - `callback_id`: The identifier of the callback to unregister

  ## Returns
    - `{:ok, :unregistered}` if the unregistration was successful
  """
  @spec unregister_change_callback(term()) :: {:ok, :unregistered}
  def unregister_change_callback(callback_id) do
    Registry.unregister_match(Arca.Config.CallbackRegistry, :config_change, {callback_id, :_})
    {:ok, :unregistered}
  end

  @doc """
  Adds a callback function to be called whenever the configuration changes.
  Unlike `register_change_callback/2`, this callback does not receive any arguments.

  Fires once per change event on every path: put, delete, reload, an externally
  detected edit, and a location switch. It previously fired twice for a single
  externally detected change. The full matrix is in the `Arca.Config` module
  documentation.

  ## Parameters
    - `callback_fn`: A 0-arity function to execute when config changes

  ## Returns
    - `{:ok, reference}` if the registration was successful, where reference is used to remove the callback
  """
  @spec add_callback(function()) :: {:ok, reference()}
  def add_callback(callback_fn) when is_function(callback_fn, 0) do
    # Generate a unique reference to identify this callback
    callback_ref = make_ref()

    # Register the callback with the registry
    Registry.register(
      Arca.Config.SimpleCallbackRegistry,
      :simple_callback,
      {callback_ref, callback_fn}
    )

    # Return the reference for later removal
    {:ok, callback_ref}
  end

  @doc """
  Removes a previously registered callback function.

  ## Parameters
    - `callback_ref`: The reference returned by `add_callback/1`

  ## Returns
    - `{:ok, :removed}` if the callback was successfully removed
    - `{:error, :not_found}` if the callback wasn't registered
  """
  @spec remove_callback(reference()) :: {:ok, :removed} | {:error, :not_found}
  def remove_callback(callback_ref) do
    # Find the exact pid and value for the callback to unregister
    case Registry.lookup(Arca.Config.SimpleCallbackRegistry, :simple_callback)
         |> Enum.find(fn {_pid, {ref, _fn}} -> ref == callback_ref end) do
      nil ->
        {:error, :not_found}

      {_pid, _value} ->
        # Unregister the specific pid/value pair
        Registry.unregister_match(
          Arca.Config.SimpleCallbackRegistry,
          :simple_callback,
          {callback_ref, :_}
        )

        {:ok, :removed}
    end
  end

  @doc """
  Notifies all registered 0-arity callbacks.
  This is called automatically whenever the configuration changes.

  ## Returns
    - `{:ok, :notified}` after all callbacks have been executed
  """
  @spec notify_callbacks() :: {:ok, :notified}
  def notify_callbacks do
    require Logger

    # Get number of callbacks for logging
    # registry_entries = Registry.lookup(Arca.Config.SimpleCallbackRegistry, :simple_callback)
    # Logger.debug("Notifying #{length(registry_entries)} simple callbacks")

    # Execute all registered callbacks
    Registry.dispatch(Arca.Config.SimpleCallbackRegistry, :simple_callback, fn entries ->
      for {_pid, {ref, callback_fn}} <- entries do
        try do
          callback_fn.()
        rescue
          e ->
            Logger.error("Simple callback error for #{inspect(ref)}: #{inspect(e)}")
        end
      end
    end)

    {:ok, :notified}
  end

  @doc """
  Loads configuration during the :load_config start phase.
  This should be called by the parent application during its start phase.

  ## Returns
    - `{:ok, config}` if configuration was loaded successfully
    - `{:error, reason}` if there was an error loading configuration
  """
  @spec load_config() :: {:ok, map()} | {:error, term()}
  def load_config do
    GenServer.call(__MODULE__, :load_config)
  end

  @doc """
  Switches the configuration file location at runtime.

  ## Parameters
    - `opts`: Keyword list with optional `:path` and `:file` keys

  ## Returns
    - `{:ok, previous_location}` with the previous path and file settings
    - `{:error, reason}` if an error occurred
  """
  @spec switch_config_location(keyword()) :: {:ok, keyword()} | {:error, term()}
  def switch_config_location(opts \\ []) do
    GenServer.call(__MODULE__, {:switch_config_location, opts})
  end

  @doc """
  Notifies all registered callback functions of an external configuration change.
  This is called by the FileWatcher when it detects changes to the config file.

  ## Returns
    - `{:ok, :notified}` after all callbacks have been notified
  """
  @spec notify_external_change() :: {:ok, :notified}
  def notify_external_change do
    # `:get_config` replies with the config map, and only ever has. The `case`
    # this replaces also had an `{:ok, conf}` clause that nothing could produce;
    # the test covering it mocked GenServer itself to fabricate the reply.
    config = GenServer.call(__MODULE__, :get_config)

    dispatch_config_callbacks(config)
    notify_callbacks()

    {:ok, :notified}
  end

  # Server callbacks

  @impl true
  def init(_) do
    # Start with empty configuration - configuration will be loaded during start phase
    {:ok, %{config: %{}, loaded: false}}
  end

  @impl true
  def handle_call(:load_config, _from, state) do
    # This is the documented first-run path, and the only caller allowed to read
    # a missing config file as an empty one (ruling R4).
    case Cfg.load(nil, bootstrap: true) do
      {:ok, config} ->
        rebuild_cache(config)

        {:reply, {:ok, config}, %{state | config: config, loaded: true}}

      {:error, _reason} = error ->
        # A real load failure (unparseable or unreadable file) is not an empty
        # config. Leave state untouched and unloaded so the caller sees the
        # failure and a later load can still succeed.
        {:reply, error, state}
    end
  end

  @impl true
  def handle_call(:get_config, _from, state) do
    {:reply, state.config, state}
  end

  @impl true
  def handle_call({:get, key_path}, _from, state) do
    state
    |> ensure_loaded()
    |> reply_to_get(key_path)
  end

  @impl true
  def handle_call({:put, key_path, value}, _from, state) do
    case read_current_config(state.config) do
      {:ok, current_config} -> reply_to_put(current_config, key_path, value, state)
      {:error, _reason} = error -> {:reply, error, state}
    end
  end

  @impl true
  def handle_call({:delete, key_path}, _from, state) do
    case read_current_config(state.config) do
      {:ok, current_config} -> reply_to_delete(current_config, key_path, state)
      {:error, _reason} = error -> {:reply, error, state}
    end
  end

  @impl true
  def handle_call(:reload, from, state), do: handle_call({:reload, :announce}, from, state)

  @impl true
  def handle_call({:reload, announcement}, _from, state) do
    case Cfg.load() do
      {:ok, config} ->
        rebuild_cache(config)
        announce(announcement, state.config, config)

        # Return success
        {:reply, {:ok, config}, %{state | config: config, loaded: true}}

      {:error, reason} = error ->
        {:reply, error, Map.put(state, :load_error, reason)}
    end
  end

  @impl true
  def handle_call({:switch_config_location, opts}, _from, state) do
    env_prefix = Cfg.env_var_prefix()
    path_var = "#{env_prefix}_CONFIG_PATH"
    file_var = "#{env_prefix}_CONFIG_FILE"

    previous_location = [path: System.get_env(path_var), file: System.get_env(file_var)]

    Arca.Config.FileWatcher.stop_watching()

    apply_location(path_var, Keyword.fetch(opts, :path))
    apply_location(file_var, Keyword.fetch(opts, :file))

    case Cfg.load() do
      {:ok, config} ->
        rebuild_cache(config)
        Arca.Config.FileWatcher.start_watching()
        notify_change(state.config, config)

        {:reply, {:ok, previous_location}, %{state | config: config, loaded: true}}

      {:error, reason} ->
        # The switch did not happen, so the previous location stays live in
        # every respect: environment variables, cache and watcher. Restoring it
        # is the same operation as applying it, which is why both branches now
        # go through `apply_location/2` instead of one being a hand-rolled
        # inverse of the other -- four copies of "value ? put_env : delete_env",
        # in two different shapes, free to drift apart.
        rebuild_cache(state.config)

        apply_location(path_var, {:ok, previous_location[:path]})
        apply_location(file_var, {:ok, previous_location[:file]})

        Arca.Config.FileWatcher.start_watching()

        {:reply, {:error, reason}, state}
    end
  end

  # Load on demand the first time a key is read before the load phase has run.
  # `:error` means the caller said nothing about this part of the location, so
  # leave it alone; `{:ok, nil}` means they explicitly cleared it.
  defp apply_location(_var, :error), do: :ok
  defp apply_location(var, {:ok, nil}), do: System.delete_env(var)
  defp apply_location(var, {:ok, value}), do: System.put_env(var, value)

  defp reply_to_put(current_config, key_path, value, state) do
    new_config = put_in_nested(current_config, key_path, value)

    case write_config(new_config) do
      :ok ->
        rebuild_cache(new_config)
        notify_write(current_config, new_config)

        {:reply, {:ok, value}, %{state | config: new_config}}

      {:error, reason} ->
        # The write did not land, so neither state nor cache may advance past
        # it: a later read must reflect the disk, not the value we failed to
        # persist. No notification either -- nothing changed.
        {:reply, {:error, reason}, state}
    end
  end

  # A key that was never set is not deleted, and saying `{:ok, :deleted}` for it
  # was the AR-1 shape on the public surface: a success return claiming an
  # effect that did not happen. The facade documented the opposite the whole
  # time -- `{:error, reason}` if the key did not exist, and a raise from
  # `delete!/1` -- so this makes the code agree with its own contract.
  defp reply_to_delete(current_config, key_path, state) do
    case get_in_nested(current_config, key_path) do
      {:ok, _value} -> write_deletion(current_config, key_path, state)
      {:error, _reason} = error -> {:reply, error, state}
    end
  end

  defp write_deletion(current_config, key_path, state) do
    new_config = delete_in_nested(current_config, key_path)

    case write_config(new_config) do
      :ok ->
        rebuild_cache(new_config)
        notify_write(current_config, new_config)

        {:reply, {:ok, :deleted}, %{state | config: new_config}}

      {:error, reason} ->
        # As for put/2: a failed write leaves state and cache exactly as they
        # were, so the deleted-looking key is still readable and still on disk.
        {:reply, {:error, reason}, state}
    end
  end

  defp ensure_loaded(%{config: config, loaded: false} = state) when map_size(config) == 0 do
    case Cfg.load() do
      {:ok, loaded_config} ->
        rebuild_cache(loaded_config)
        {:ok, %{state | config: loaded_config, loaded: true}}

      {:error, reason} ->
        # Stay unloaded so a later read retries. Marking the failure as "loaded"
        # turned every subsequent key into "Key not found" and lost the cause.
        {:error, reason, state}
    end
  end

  defp ensure_loaded(state), do: {:ok, state}

  defp reply_to_get({:ok, state}, key_path) do
    {:reply, get_in_nested(state.config, key_path), state}
  end

  defp reply_to_get({:error, reason, state}, _key_path) do
    {:reply, {:error, reason}, state}
  end

  # Read the configuration currently on disk, so a write merges into whatever is
  # actually there rather than into what this process last saw.
  #
  # A file that exists but cannot be read or parsed is NOT treated as absent.
  # This runs immediately before the file is overwritten, so folding a decode
  # failure into the in-memory config meant a configuration a person had
  # hand-edited into invalid JSON was silently discarded and replaced on the
  # next `put/2` -- data loss with no log line, no error, and no trace. The
  # watcher already refuses to do this (`reload_tolerantly/0` keeps its last
  # good config and says so); this path used to erase instead.
  #
  # A file that is simply not there yet is the ordinary first-write case, and
  # the in-memory config is the right base for it.
  @spec read_current_config(map()) :: {:ok, map()} | {:error, term()}
  defp read_current_config(fallback_config) do
    config_path = Cfg.config_file() |> Path.expand()

    case File.read(config_path) do
      {:ok, content} -> decode_current_config(content, config_path)
      {:error, :enoent} -> {:ok, fallback_config}
      {:error, reason} -> Error.load_failed(reason)
    end
  end

  defp decode_current_config(content, config_path) do
    require Logger

    case Jason.decode(normalize_config_content(content)) do
      {:ok, config} ->
        {:ok, config}

      {:error, _reason} ->
        Logger.error(
          "Refusing to overwrite #{config_path}: it exists but is not valid JSON. " <>
            "Fix or remove the file; no configuration was changed."
        )

        Error.load_failed("Existing config file is not valid JSON")
    end
  end

  # An empty file is an empty configuration, matching `Cfg.load/2`.
  defp normalize_config_content(""), do: "{}"
  defp normalize_config_content(content), do: content

  # Private functions

  defp normalize_key_path(key) when is_list(key), do: key

  defp normalize_key_path(key) do
    key
    |> to_string()
    |> String.split(".")
  end

  # `asked_for` is the whole key path the caller used, carried down the recursion
  # so a failure can report the key that was actually asked for rather than
  # whichever suffix the walk happened to stop on.
  defp get_in_nested(config, key_path), do: get_in_nested(config, key_path, key_path)

  # Base case: reached leaf value successfully
  defp get_in_nested(result, [], _asked_for), do: {:ok, result}

  # Error case: current position is not a map but we need to go deeper
  defp get_in_nested(current, [_head | _tail], asked_for) when not is_map(current),
    do: Error.not_found(asked_for)

  # Recursive case: get value at current key and continue
  defp get_in_nested(config, [head | tail], asked_for) do
    case Map.get(config, head) do
      nil -> Error.not_found(asked_for)
      value -> get_in_nested(value, tail, asked_for)
    end
  end

  # Base case: leaf key - directly update the map
  defp put_in_nested(config, [last_key], value) do
    Map.put(config, last_key, value)
  end

  # Recursive case: need to traverse deeper
  defp put_in_nested(config, [head | tail], value) do
    current_value = get_map_value(config, head)
    updated_value = put_in_nested(current_value, tail, value)

    Map.put(config, head, updated_value)
  end

  # Helper to ensure we're working with a map for nested operations
  defp get_map_value(config, key) do
    case Map.get(config, key) do
      nil -> %{}
      val when is_map(val) -> val
      _non_map -> %{}
    end
  end

  # Base case: leaf key - delete the key from map
  defp delete_in_nested(config, [last_key]) do
    Map.delete(config, last_key)
  end

  # Recursive case: need to traverse deeper
  defp delete_in_nested(config, [head | tail]) do
    case Map.get(config, head) do
      nil ->
        # If key doesn't exist, return config unchanged
        config

      submap when is_map(submap) ->
        # Go deeper
        updated_submap = delete_in_nested(submap, tail)

        # If map is empty after deletion, remove it too
        if map_size(updated_submap) == 0 do
          Map.delete(config, head)
        else
          Map.put(config, head, updated_submap)
        end

      _non_map ->
        # If value at key is not a map, can't traverse further, return unchanged
        config
    end
  end

  # Write configuration to the current config file.
  # Returns :ok, or {:error, reason} when the write did not reach the disk --
  # callers must not advance any state on the error branch.
  @spec write_config(map()) :: :ok | {:error, term()}
  defp write_config(config) do
    require Logger

    # Always get a fresh config file path to ensure we have the latest environment settings
    # This is critical when environment variables change during runtime
    # IMPORTANT: Always fully expand paths to prevent recursive directory creation issues
    # Path.expand converts paths like "./.config/" or "/abs/path" to their absolute form
    expanded_config_path = Cfg.config_file() |> Path.expand()

    # Register a unique write token to avoid self-notifications
    token = System.monotonic_time()
    Arca.Config.FileWatcher.register_write(token)

    # Encode configuration
    encoded_config = Jason.encode!(config, pretty: true)

    # Ensure parent directory exists and file exists before writing
    # This now explicitly creates the directory/file only when needed for writing
    with :ok <- Arca.Config.FileWatcher.ensure_config_exists(config, true),
         :ok <- File.write(expanded_config_path, encoded_config) do
      :ok
    else
      {:error, reason} ->
        Logger.error("Failed to write config file #{expanded_config_path}: #{inspect(reason)}")
        Error.write_failed(reason)
    end
  end

  defp announce(:announce, previous_config, current_config),
    do: notify_change(previous_config, current_config)

  defp announce(:announce_if_changed, previous_config, current_config),
    do: notify_write(previous_config, current_config)

  # A write that changed nothing is not a change, so it raises no event. This
  # covers both the application's own writes and the ones the watcher finds on
  # disk, which is why our writes never arrive back as external changes. It is
  # also what stops a callback which writes a derived value from re-triggering
  # itself forever -- a loop that only became reachable when callbacks started
  # firing on the write paths.
  defp notify_write(config, config), do: :ok

  defp notify_write(previous_config, current_config),
    do: notify_change(previous_config, current_config)

  # The single notification path for every mutation: put, delete, reload,
  # externally detected change, and location switch. Each channel fires exactly
  # once per event -- per-key subscribers for the paths whose value changed,
  # config callbacks and simple callbacks once each.
  #
  # A (re)load is an event in its own right, even when the values come back
  # identical: the caller asked for it, and a consumer may be holding derived
  # state it wants refreshed. Per-key subscribers are still told only about the
  # paths whose value actually changed.
  defp notify_change(previous_config, current_config) do
    notify_subscribers(previous_config, current_config)
    dispatch_callbacks_async(current_config)
    :ok
  end

  # Only subscribed paths are examined, so this costs nothing when nobody is
  # listening. Comparing values rather than walking the written path and its
  # ancestors also reaches the subscriber whose value changed because an
  # ancestor map was replaced -- the case the ancestor walk could never see.
  defp notify_subscribers(previous_config, current_config) do
    Arca.Config.Registry
    |> Registry.select([{{:"$1", :_, :_}, [], [:"$1"]}])
    |> Enum.uniq()
    |> Enum.each(fn path ->
      notify_if_changed(path, value_at(previous_config, path), value_at(current_config, path))
    end)
  end

  # Repeated variable in the head: same value before and after means no news.
  defp notify_if_changed(_path, value, value), do: :ok

  defp notify_if_changed(path, _previous_value, current_value) do
    Registry.dispatch(Arca.Config.Registry, path, fn entries ->
      for {pid, _registered_value} <- entries do
        send(pid, {:config_updated, path, current_value})
      end
    end)
  end

  defp value_at(config, path) do
    case get_in_nested(config, path) do
      {:ok, value} -> value
      {:error, _reason} -> nil
    end
  end

  # Consumer callbacks run outside the server process. A callback that calls
  # back into Arca.Config -- to read the new value, or to write a derived one --
  # would otherwise deadlock against the very mutation that triggered it, and
  # widening the matrix means callbacks now fire on paths where that is reachable.
  defp dispatch_callbacks_async(config) do
    require Logger

    Arca.Config.TaskSupervisor
    |> Task.Supervisor.start_child(fn ->
      dispatch_config_callbacks(config)
      notify_callbacks()
    end)
    |> case do
      {:ok, _pid} ->
        :ok

      {:error, reason} ->
        # The write itself landed, so this does not fail the caller -- but the
        # matrix promises each channel fires once per change event, and this is
        # the only place that can tell anyone it did not.
        Logger.error(
          "Configuration changed but callbacks could not be dispatched: #{inspect(reason)}"
        )

        :ok
    end
  end

  defp dispatch_config_callbacks(config) do
    require Logger

    Registry.dispatch(Arca.Config.CallbackRegistry, :config_change, fn entries ->
      for {_process_pid, {id, callback_fn}} <- entries do
        try do
          callback_fn.(config)
        rescue
          e ->
            Logger.error("Config change callback error: #{inspect(id)}: #{inspect(e)}")
        end
      end
    end)

    :ok
  end

  # Repopulate the cache from a freshly loaded config. Clearing first reports in
  # one call whether the cache is available at all, so a cache that is down
  # costs one line rather than one per key.
  defp rebuild_cache(config) do
    case Cache.clear() do
      {:ok, :cleared} ->
        flatten_and_cache(config)
        :ok

      {:error, :cache_unavailable} = error ->
        report_cache_result(error)
    end
  end

  # The disk write is the contract; the cache only accelerates reads in front of
  # it. A cache that is down has no table at all, so it cannot serve a stale
  # value -- the next read falls through to server state. Report the degradation
  # rather than discarding it, but do not fail a write that did land on disk.
  defp report_cache_result({:ok, _result}), do: :ok

  defp report_cache_result({:error, :cache_unavailable}) do
    require Logger

    Logger.warning(
      "Config cache unavailable; reads fall through to server state until it restarts"
    )

    :ok
  end

  defp flatten_and_cache(config, prefix \\ []) do
    if is_map(config) do
      # Cache this level
      if prefix != [] do
        Cache.put(prefix, config)
      end

      # Recursively cache all nested values
      Enum.each(config, fn {key, value} ->
        new_prefix = prefix ++ [key]
        Cache.put(new_prefix, value)

        if is_map(value) do
          flatten_and_cache(value, new_prefix)
        end
      end)
    end
  end
end
