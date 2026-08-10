defmodule Arca.Config.FileWatcher do
  @moduledoc """
  Watches the configuration file for changes and triggers reloads.

  This module monitors the configuration file for changes made outside
  of the application and ensures the in-memory configuration stays in sync
  with the file on disk. It also prevents notification loops from
  changes made by the application itself.

  The FileWatcher starts in dormant state and only begins monitoring after
  configuration is loaded during the start phase.
  """

  use GenServer

  # 5 seconds
  @check_interval 5_000

  @doc """
  Starts the file watcher process.
  """
  def start_link(_) do
    GenServer.start_link(__MODULE__, nil, name: __MODULE__)
  end

  @doc """
  Registers a write operation.

  Self-notification is prevented by comparing configurations rather than by
  suppressing changes in a time window: a change the application made produces a
  configuration identical to the one already in memory, so no change event is
  raised for it. The token is recorded in the watcher's state and is retained
  for compatibility and diagnostics; it no longer gates whether a detected
  change is acted on, because doing so lost external edits that landed inside
  the window.

  ## Parameters
    - `token`: A unique token identifying the write operation
  """
  def register_write(token) do
    GenServer.cast(__MODULE__, {:register_write, token})
  end

  @doc """
  Starts file watching after configuration has been loaded.
  This should be called after the configuration is loaded during the start phase.

  ## Parameters
    - `config_file`: Optional specific config file path to watch. If not provided,
      uses the path from `Arca.Config.Cfg.config_file/0`

  ## Returns
    - `{:ok, :watching}` once the watcher is armed on the resolved file

  Synchronous, like `stop_watching/0`. It used to be a cast typed `:: :ok`,
  which means a cast to a dead watcher also answered `:ok` -- and since the
  watcher restarts dormant and nothing but this call re-arms it, a crash left
  external change detection off for the life of the VM with every caller having
  been told it was on.
  """
  @spec start_watching(String.t() | nil) :: {:ok, :watching}
  def start_watching(config_file \\ nil) do
    GenServer.call(__MODULE__, {:start_watching, config_file})
  end

  @doc """
  Stops file watching.

  This function stops the FileWatcher from monitoring the configuration file.
  It can be called when switching configuration locations or during shutdown.

  ## Returns
    - `:ok` when file watching has been stopped
  """
  @spec stop_watching() :: :ok
  def stop_watching do
    GenServer.call(__MODULE__, :stop_watching)
  end

  @doc """
  Ensures the configuration directory and file exist.

  This function creates the config directory if it doesn't exist
  and creates an empty config file if one doesn't exist yet.

  ## Parameters
    - `initial_config`: Optional map with default configuration values (defaults to empty map)
    - `create_if_missing`: Whether to create the directory and file if missing (defaults to true)

  ## Returns
    - `:ok` if the directory and file were created successfully or if creation was skipped
    - `{:error, reason}` if an error occurred
  """
  @spec ensure_config_exists(map(), boolean()) :: :ok | {:error, term()}
  def ensure_config_exists(initial_config \\ %{}, create_if_missing \\ true) do
    # Use Arca.Config.Cfg.config_file() which now properly expands paths
    config_file = Arca.Config.Cfg.config_file() |> Path.expand()
    config_dir = Path.dirname(config_file)

    # Only create directories/files if explicitly requested
    if create_if_missing do
      with :ok <- ensure_directory_exists(config_dir) do
        ensure_file_exists(config_file, initial_config)
      end
    else
      # Skip file creation if not requested
      :ok
    end
  end

  # Server callbacks

  @impl true
  def init(_) do
    # Dormant until the configuration has been loaded: at application boot the
    # start phase arms this, and there may be no config file yet.
    #
    # On a *restart*, though, the application is already up and the start phase
    # will not run again -- so a watcher that crashed once used to come back
    # dormant and stay that way forever. If a config file is already resolvable
    # we are in that second case, and re-arm ourselves.
    {:ok,
     %{config_file: nil, last_info: nil, write_token: nil, watching: false, check_timer: nil},
     {:continue, :rearm_if_configured}}
  end

  @impl true
  def handle_continue(:rearm_if_configured, state) do
    config_file = Arca.Config.Cfg.config_file() |> Path.expand()

    case File.exists?(config_file) do
      true -> {:noreply, start_watching_state(config_file, state)}
      false -> {:noreply, state}
    end
  end

  @impl true
  def handle_call({:start_watching, config_file}, _from, state) do
    file_to_watch = config_file || Arca.Config.Cfg.config_file()

    {:reply, {:ok, :watching}, start_watching_state(file_to_watch, state)}
  end

  @impl true
  def handle_call(:stop_watching, _from, state) do
    cancel_check(state[:check_timer])

    {:reply, :ok,
     %{config_file: nil, last_info: nil, write_token: nil, watching: false, check_timer: nil}}
  end

  @impl true
  def handle_cast({:register_write, token}, state) do
    # Register that we've written to the file (to avoid self-notification)
    {:noreply, %{state | write_token: token}}
  end

  # Dormant: do not reschedule. A check already in the mailbox when watching
  # stopped used to re-arm the timer and quietly resurrect a stopped watcher;
  # start_watching/1 is the only thing that starts the cycle.
  @impl true
  def handle_info(:check_file, %{watching: false} = state) do
    {:noreply, %{state | check_timer: nil}}
  end

  @impl true
  def handle_info(:check_file, %{last_info: last_info} = state) do
    # Always refresh the config path in case it changed due to environment changes
    updated_path = Arca.Config.Cfg.config_file() |> Path.expand()
    current_info = get_file_info(updated_path)

    report_lost_file(current_info, last_info, updated_path, state.config_file)
    reload_if_changed(current_info, last_info)

    {:noreply,
     %{
       state
       | last_info: current_info,
         config_file: updated_path,
         write_token: nil,
         check_timer: schedule_check()
     }}
  end

  # Private functions

  # Every detected change is reloaded; whether anyone hears about it is decided
  # by whether the config actually differs from what is already in memory. That
  # is what makes our own writes self-evidently not external changes, and it is
  # why there is no longer a suppression window for an external edit to be lost
  # in: the old code dropped any change while a write token was set, and
  # advanced past it so it was never seen again.
  defp reload_if_changed(current_info, last_info) do
    case file_changed?(current_info, last_info) do
      true -> reload_tolerantly()
      false -> :ok
    end
  end

  # A config file can be edited into an unparseable state by hand at any moment.
  # Hard-matching a successful reload here meant one bad edit raised a
  # MatchError and the watcher restarted into permanent, silent dormancy.
  defp reload_tolerantly do
    require Logger

    case Arca.Config.Server.reload_external() do
      {:ok, _config} ->
        :ok

      {:error, reason} ->
        Logger.warning(
          "Config file changed but could not be loaded: #{inspect(reason)}. " <>
            "Keeping the last good configuration and continuing to watch."
        )

        :ok
    end
  end

  # The one place that arms the watcher, used by `start_watching/1` and by the
  # re-arm after a supervisor restart.
  defp start_watching_state(file_to_watch, state) do
    cancel_check(state[:check_timer])

    %{
      state
      | config_file: file_to_watch,
        last_info: get_file_info(file_to_watch),
        watching: true,
        check_timer: schedule_check()
    }
  end

  defp cancel_check(nil), do: :ok
  defp cancel_check(timer), do: Process.cancel_timer(timer)

  defp schedule_check do
    Process.send_after(self(), :check_file, @check_interval)
  end

  # A file we cannot stat reads as `nil`, and `file_changed?(nil, _)` is false --
  # so "unreadable" and "unmodified" produce the same answer. That silence is
  # reported exactly once, on the transition, by `report_lost_file/3`: logging
  # on every tick would bury the signal under a line per second.
  defp get_file_info(path) do
    case File.stat(path) do
      {:ok, info} -> info
      {:error, _reason} -> nil
    end
  end

  # Losing sight of the file is an event. Regaining it is handled already: the
  # next successful stat differs from `nil`, so `file_changed?/2` reports a
  # change and the reload runs.
  #
  # The path is re-resolved every tick, so it can differ from the one looked at
  # last time -- an environment change moved it. That is a location change, not
  # a lost file: `last_info` describes a different file entirely, and warning
  # about it reports the absence of a file nobody said was there.
  defp report_lost_file(_current_info, _last_info, path, previous_path)
       when path != previous_path,
       do: :ok

  defp report_lost_file(nil, nil, _path, _previous_path), do: :ok

  defp report_lost_file(nil, _last_info, path, _previous_path) do
    require Logger

    Logger.warning(
      "Configuration file #{path} can no longer be read; keeping the last known configuration " <>
        "and continuing to watch."
    )
  end

  defp report_lost_file(_current_info, _last_info, _path, _previous_path), do: :ok

  defp file_changed?(nil, _), do: false
  defp file_changed?(_, nil), do: true

  defp file_changed?(current, last) do
    current.mtime != last.mtime || current.size != last.size
  end

  defp ensure_directory_exists(dir) do
    case File.mkdir_p(dir) do
      :ok -> :ok
      {:error, :eexist} -> :ok
      {:error, reason} -> {:error, "Failed to create config directory: #{reason}"}
    end
  end

  defp ensure_file_exists(file_path, initial_config) do
    if File.exists?(file_path) do
      :ok
    else
      content = Jason.encode!(initial_config, pretty: true)

      case File.write(file_path, content) do
        :ok -> :ok
        {:error, reason} -> {:error, "Failed to create config file: #{reason}"}
      end
    end
  end
end
