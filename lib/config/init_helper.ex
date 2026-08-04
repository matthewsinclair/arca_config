defmodule Arca.Config.InitHelper do
  @moduledoc """
  Provides helper functions for initializing configuration for applications using Arca.Config.

  This module helps application developers ensure that configuration directories and files
  exist before the Arca.Config system attempts to load them.
  """

  alias Arca.Config.FileWatcher
  alias Arca.Config.Cfg

  @doc """
  Initializes the configuration for an application.

  This function:
  1. Ensures the configuration directory exists
  2. Creates a default configuration file if one doesn't exist
  3. Returns the location of the configuration file

  ## Parameters
    - `app_name`: The name of the application (atom) - will be used to determine config domain
    - `initial_config`: A map containing initial configuration values (default: %{})
    
  ## Returns
    - `{:ok, config_path}` if initialization succeeded
    - `{:error, reason}` if initialization failed
  """
  @spec init_config(atom(), map()) :: {:ok, String.t()} | {:error, term()}
  def init_config(app_name, initial_config \\ %{}) do
    # Set the config domain to the app name
    Application.put_env(:arca_config, :config_domain, app_name)

    # Get the config file path that will be used
    config_file = Cfg.config_file() |> Path.expand()

    # Ensure config directory and file exist - force creation since this is explicit
    with :ok <- FileWatcher.ensure_config_exists(initial_config, true) do
      {:ok, config_file}
    end
  end

  @doc """
  Sets up a default configuration directory relative to the working directory.

  This function creates a directory like `.app_name/` in the current working
  directory and ensures a config.json file exists within it. It also sets
  `<APP_NAME>_CONFIG_PATH`, `<APP_NAME>_CONFIG_FILE` and the config domain, so
  it changes global state for the whole VM, not just its return value.

  ## Parameters
    - `app_name`: The name of the application as an atom (e.g., `:my_app`)
    - `initial_config`: A map containing initial configuration values (default: %{})
    
  ## Returns
    - `{:ok, config_path}` if the setup succeeded
    - `{:error, reason}` if the setup failed
  """
  @spec setup_default_config(atom(), map()) :: {:ok, String.t()} | {:error, term()}
  def setup_default_config(app_name, initial_config \\ %{}) do
    app_str = to_string(app_name)
    # Use the current directory instead of home directory
    # This keeps all test files contained within the project
    config_dir = Path.join(File.cwd!(), ".#{app_str}")
    config_file = Path.join(config_dir, "config.json")

    # Set environment variables to override defaults
    System.put_env("#{String.upcase(app_str)}_CONFIG_PATH", config_dir)
    System.put_env("#{String.upcase(app_str)}_CONFIG_FILE", "config.json")

    # Set the config domain
    Application.put_env(:arca_config, :config_domain, app_name)

    # The environment variables and domain above are already set, so the
    # resolved location IS `config_file` -- which is why this can use the one
    # implementation rather than its own copy. `ensure_directory_exists/1` and
    # `ensure_file_exists/2` used to live here as well, byte-identical to
    # `FileWatcher`'s (audit finding AF-12): two places to change the rule for
    # creating a configuration location, and no way to notice when only one
    # of them changed.
    with :ok <- FileWatcher.ensure_config_exists(initial_config, true) do
      {:ok, config_file}
    end
  end
end
