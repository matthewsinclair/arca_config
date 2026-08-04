defmodule Arca.Config.Cfg do
  @moduledoc """
  Resolves where the configuration lives, loads it, and reads it from disk.

  ## What this module owns

  This is the **location and load authority**: `config_file/0`, `config_pathname/0`,
  `config_filename/0`, `config_location/0`, `env_var_prefix/0` and `load/2`. Every
  other module in the library asks this one where the configuration is --
  `Server`, `FileWatcher` and `InitHelper` all resolve through it -- and these
  functions are pure over the environment and the filesystem, so they answer
  without a running server.

  It was aliased `LegacyCfg` inside `Server` for a long time while being the live
  loader on every load, reload and switch path. It is not legacy.

  What it does *not* own is nested get and put. `get/1`, `get!/1`, `put/2` and
  `put!/2` are kept as public API and now delegate to `Arca.Config.Server`, which
  holds the state, the cache and the notifications. They used to be a second
  implementation of the same idea that read straight from disk, wrote straight to
  disk, and never told the server or the cache -- so a value written here and a
  value read there could disagree until the file watcher intervened.

  This module derives configuration paths and filenames from the config domain.

  The domain is `Application.get_env(:arca_config, :config_domain)` if set, and
  `:arca_config` otherwise. It is not guessed.

  ## Where the configuration file lives

  One directory and one filename are resolved, each from the first tier that
  answers:

  | Priority | Directory                                       | Filename                                        |
  | ---------- | ------------------------------------------------- | ------------------------------------------------- |
  | 1 highest | `<DOMAIN>_CONFIG_PATH` env var                  | `<DOMAIN>_CONFIG_FILE` env var                  |
  | 2        | `ARCA_CONFIG_PATH` env var                       | `ARCA_CONFIG_FILE` env var                       |
  | 3        | `config :arca_config, config_path:`             | `config :arca_config, config_file:`             |
  | 4 lowest | `.<domain>/`, relative to the working directory | `config.json`                                    |

  `<DOMAIN>` is the config domain upcased, so a domain of `:my_app` reads
  `MY_APP_CONFIG_PATH`. **The domain-specific variable wins over the generic
  one**, which is the opposite of what this library's README claimed for a long
  time, and is why a downstream project's test isolation set `ARCA_CONFIG_PATH`
  across nine files and never once took effect.

  The resolved location does not depend on which files exist. `config_file/0`
  returns the configured location whether or not anything is there yet, so a
  write creates the file the caller asked for rather than being redirected
  somewhere else the moment the configured one is missing.

  ## Important Notes

  - Parent applications MUST set the config domain in their `Application.start/2` callback
    before calling `Arca.Config.load_config_phase/0` during the start phase
  - The config domain is checked on every access to ensure consistency
  """

  alias Arca.Config.Server

  @doc """
  The configuration domain: either what the parent application configured, or
  `:arca_config`.

  The domain decides the environment variable prefix and the default
  directory name, so it has to be the same answer every time it is asked. It
  used to be guessed when unset -- by walking the `$callers` process dictionary
  and then taking the first non-system entry from `Application.started_applications/0`
  -- which returned whichever application happened to be started and in which
  order. A probe resolved it to `:elixir_uuid`, an unused dependency; running
  the test suite resolved it to `:ex_unit`. Set it explicitly:

      Application.put_env(:arca_config, :config_domain, :my_app)
  """
  @spec config_domain() :: atom()
  def config_domain do
    Application.get_env(:arca_config, :config_domain, :arca_config)
  end

  @doc false
  def env_var_prefix do
    config_domain() |> to_string() |> String.upcase()
  end

  @doc """
  Loads configuration from the specified file, or auto-detects from configured paths.

  When no file is explicitly provided, it first checks for a configuration file in the
  configured path (.app_name/config.json).

  ## Parameters
    - `config_file`: The path to the configuration file (optional).

  ## Examples
      iex> test_file = Path.join(System.tmp_dir!(), "arca_cfg_load_doctest.json")
      iex> File.write!(test_file, ~s({"id": "TEST_CONFIG"}))
      iex> {:ok, cfg} = Arca.Config.Cfg.load(test_file)
      iex> cfg["id"]
      "TEST_CONFIG"
      iex> File.rm(test_file)
      :ok
  """
  @spec load(String.t() | nil, keyword()) :: {:ok, map()} | {:error, String.t()}
  def load(config_file \\ nil, opts \\ []) do
    (config_file || config_file())
    |> Path.expand()
    |> File.read()
    |> handle_file_read_result(Keyword.get(opts, :bootstrap, false))
  end

  defp handle_file_read_result({:ok, content}, _bootstrap) do
    content
    |> normalize_content()
    |> Jason.decode()
    |> handle_decode_result()
  end

  # First-run bootstrap only (ST0002 ruling R4). A missing config file is an
  # empty config when the caller is the initial load phase, and an error
  # everywhere else -- otherwise a typo'd or vanished location reads as a
  # successful load of nothing.
  defp handle_file_read_result({:error, :enoent}, true), do: {:ok, %{}}

  defp handle_file_read_result({:error, reason}, _bootstrap),
    do: {:error, "Failed to load config file: #{reason}"}

  defp normalize_content(""), do: "{}"
  defp normalize_content(content), do: content

  defp handle_decode_result({:ok, result}), do: {:ok, result}

  defp handle_decode_result({:error, %{position: position, token: token}}) do
    {:error, "Error parsing config at position: #{position}, token: '#{token}'"}
  end

  @doc """
  Get fully-qualified path name of the configuration file.

  Looks first in the home directory, then falls back to the local directory
  if no configuration is found in the home path.

  ## Examples
      iex> app_specific_path_var = Arca.Config.Cfg.env_var_prefix() <> "_CONFIG_PATH"
      iex> app_specific_file_var = Arca.Config.Cfg.env_var_prefix() <> "_CONFIG_FILE"
      iex> System.put_env(app_specific_path_var, Path.join(System.tmp_dir!(), "test_config"))
      iex> System.put_env(app_specific_file_var, "test.json")
      iex> String.ends_with?(Arca.Config.Cfg.config_file(), "test.json")
      true
      iex> System.delete_env(app_specific_path_var)
      iex> System.delete_env(app_specific_file_var)
  """
  @spec config_file() :: String.t()
  def config_file do
    config_pathname()
    |> Path.join(config_filename())
    |> Path.expand()
  end

  @doc """
  Get the directory holding the configuration file.

  Resolved in this order, highest priority first:

  1. `<DOMAIN>_CONFIG_PATH` -- environment variable derived from the config
     domain (eg `MY_APP_CONFIG_PATH`)
  2. `ARCA_CONFIG_PATH` -- generic environment variable
  3. `Application.get_env(:arca_config, :config_path)`
  4. `default_config_path/0` -- `.<domain>/`, relative to the working directory

  The result is always an absolute path. Every tier is expanded the same way:
  values from environment variables used to be returned verbatim, so that a
  test asserting string identity against a trailing slash would pass, while
  every other tier was expanded.

  ## Examples
      iex> app_specific_env_var = Arca.Config.Cfg.env_var_prefix() <> "_CONFIG_PATH"
      iex> System.put_env(app_specific_env_var, "/test/path")
      iex> Arca.Config.Cfg.config_pathname()
      "/test/path"
      iex> System.delete_env(app_specific_env_var)
  """
  @spec config_pathname() :: String.t()
  def config_pathname do
    {_source, path} = resolved_pathname()
    Path.expand(path)
  end

  @doc """
  Get path for the local configuration file (in current working directory).

  **Not part of configuration-file resolution.** `config_file/0` resolves one
  location, from `config_pathname/0`, and stays there. It used to return this
  path instead whenever the configured file did not happen to exist yet, so a
  write to a configured-but-absent file landed somewhere the caller never asked
  for -- in one probe, inside the repository itself.

  Looks for configuration in the following order:
  1. Environment variable derived from parent app name (e.g., `MY_APP_LOCAL_CONFIG_PATH`)
  2. Environment variable named `ARCA_LOCAL_CONFIG_PATH`
  3. Application config under `:arca_config, :local_config_path`
  4. Default local path based on parent application name

  ## Examples 
      iex> app_specific_env_var = Arca.Config.Cfg.env_var_prefix() <> "_LOCAL_CONFIG_PATH"
      iex> System.put_env(app_specific_env_var, "/test/local/path")
      iex> Arca.Config.Cfg.local_config_pathname()
      "/test/local/path"
      iex> System.delete_env(app_specific_env_var)
  """
  @spec local_config_pathname() :: String.t()
  def local_config_pathname do
    app_specific_env_var = "#{env_var_prefix()}_LOCAL_CONFIG_PATH"
    default_arca_env_var = "ARCA_LOCAL_CONFIG_PATH"

    path =
      System.get_env(app_specific_env_var) ||
        System.get_env(default_arca_env_var) ||
        Application.get_env(:arca_config, :local_config_path) ||
        local_config_path()

    # Return expanded path to avoid path joining issues
    Path.expand(path)
  end

  @doc """
  Get path for data files related to the configuration.

  ## Examples
      iex> app_specific_env_var = Arca.Config.Cfg.env_var_prefix() <> "_CONFIG_PATH"
      iex> System.put_env(app_specific_env_var, "/test/path")
      iex> Arca.Config.Cfg.config_data_pathname()
      "/test/path/data/links"
      iex> System.delete_env(app_specific_env_var)
  """
  @spec config_data_pathname() :: String.t()
  def config_data_pathname do
    Path.join([config_pathname(), "data", "links"])
  end

  @doc """
  Get name of the configuration file.

  Looks for configuration in the following order:
  1. Environment variable derived from parent app name (e.g., `MY_APP_CONFIG_FILE`)
  2. Environment variable named `ARCA_CONFIG_FILE`
  3. Application config under `:arca_config, :config_file`
  4. Default filename ("config.json")

  ## Examples
      iex> app_specific_env_var = Arca.Config.Cfg.env_var_prefix() <> "_CONFIG_FILE"
      iex> System.put_env(app_specific_env_var, "test.json")
      iex> Arca.Config.Cfg.config_filename()
      "test.json"
      iex> System.delete_env(app_specific_env_var)
  """
  @spec config_filename() :: String.t()
  def config_filename do
    {_source, filename} = resolved_filename()

    # A configured value carrying a directory keeps only its last segment, so
    # `.my_app/` joined with `/Users/x/.my_app/config.json` cannot produce a
    # doubled path. `Path.basename/1` is a no-op on a bare filename, so the
    # branch this replaces was never doing anything the call does not do.
    Path.basename(filename)
  end

  @doc """
  Report the resolved configuration location and which tier answered for it.

  Answers the question every consumer debugging a config problem actually asks:
  not "what are the rules" but "which file are you reading, and why that one".
  arca_cli's isolation set `ARCA_CONFIG_PATH` across nine files and silently had
  no effect for months, because the domain-specific variable outranks it; this
  function reports `:env_domain` in that situation and ends the guessing.

  Path and filename resolve independently through the same four tiers, so each
  reports its own source: `:env_domain`, `:env_generic`, `:app_config`, or
  `:default`. Both are read live, so the answer reflects the environment now.

  The result is a map rather than the keyword list `switch_config_location/1`
  trades in, and deliberately so -- these are resolved facts, not options. That
  function returns the *previous environment variables*, whose values may be nil
  precisely because nothing was set; feeding a resolved location back into it
  would pin a location that was previously free to move.

  ## Returns
    - `{:ok, location}` where location has `:path`, `:file`, `:config_file` and
      a `:source` map keyed by `:path` and `:file`

  ## Examples
      iex> {:ok, location} = Arca.Config.Cfg.config_location()
      iex> location.config_file == Arca.Config.Cfg.config_file()
      true
      iex> location.source.path in [:env_domain, :env_generic, :app_config, :default]
      true
  """
  @spec config_location() ::
          {:ok,
           %{
             path: String.t(),
             file: String.t(),
             config_file: String.t(),
             source: %{path: atom(), file: atom()}
           }}
  def config_location do
    {path_source, _path} = resolved_pathname()
    {file_source, _file} = resolved_filename()

    {:ok,
     %{
       path: config_pathname(),
       file: config_filename(),
       config_file: config_file(),
       source: %{path: path_source, file: file_source}
     }}
  end

  # The one ordered tier list for the config directory. `config_pathname/0`
  # projects the value out of it and `config_location/0` projects the source, so
  # a reported source cannot drift from the resolution that actually happened --
  # which it would the moment the source was derived from a second copy of this
  # chain.
  @spec resolved_pathname() :: {atom(), String.t()}
  defp resolved_pathname do
    first_present([
      {:env_domain, System.get_env("#{env_var_prefix()}_CONFIG_PATH")},
      {:env_generic, System.get_env("ARCA_CONFIG_PATH")},
      {:app_config, Application.get_env(:arca_config, :config_path)},
      {:default, default_config_path()}
    ])
  end

  @spec resolved_filename() :: {atom(), String.t()}
  defp resolved_filename do
    first_present([
      {:env_domain, System.get_env("#{env_var_prefix()}_CONFIG_FILE")},
      {:env_generic, System.get_env("ARCA_CONFIG_FILE")},
      {:app_config, Application.get_env(:arca_config, :config_file)},
      {:default, default_config_file()}
    ])
  end

  # The last tier always yields a value, so this always finds one.
  @spec first_present([{atom(), String.t() | nil}]) :: {atom(), String.t()}
  defp first_present(tiers) do
    Enum.find(tiers, fn {_source, value} -> not is_nil(value) end)
  end

  @doc """
  Inspects a configuration property by its name. Note: this will _not_ traverse the property hierarchy for nested properties.

  ## Parameters
    - `name`: The name of the property to inspect.

  ## Examples
      iex> test_path = System.tmp_dir!()
      iex> test_file = "config_test.json"
      iex> app_specific_path_var = Arca.Config.Cfg.env_var_prefix() <> "_CONFIG_PATH"
      iex> app_specific_file_var = Arca.Config.Cfg.env_var_prefix() <> "_CONFIG_FILE"
      iex> System.put_env(app_specific_path_var, test_path)
      iex> System.put_env(app_specific_file_var, test_file)
      iex> File.write!(Path.join(test_path, test_file), ~s({"id": "TEST_ID"}))
      iex> Arca.Config.Cfg.inspect_property("id")
      {:ok, "TEST_ID"}
      iex> File.rm(Path.join(test_path, test_file))
      iex> System.delete_env(app_specific_path_var)
      iex> System.delete_env(app_specific_file_var)
  """
  @spec inspect_property(String.t() | atom()) :: {:ok, any()} | {:error, String.t()}
  def inspect_property(name) do
    with {:ok, config} <- load(),
         value when not is_nil(value) <- Map.get(config, name) do
      {:ok, value}
    else
      nil -> {:error, "No such property: #{inspect(name)}"}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Provides a map-style accessor to the configuration properties.

  Delegates to `Arca.Config.Server.get/1`, which is the one nested lookup in the
  library. This used to walk the configuration itself, freshly loaded from disk
  on every call and bypassing the cache, and reported a missing key as
  `"'<key>' not found"` where the server said `"Key not found"` -- two
  implementations of one idea, disagreeing about how to say no.

  ## Parameters
    - `key`: The key to retrieve from the configuration.

  ## Examples
      iex> {:ok, _} = Arca.Config.Cfg.put("database.host", "localhost")
      iex> Arca.Config.Cfg.get("database.host")
      {:ok, "localhost"}
  """
  @spec get(String.t() | atom()) :: {:ok, any()} | {:error, String.t()}
  def get(key), do: Server.get(key)

  @doc """
  Gets the configuration property and raises an error if not found.

  ## Parameters
    - `key`: The key to retrieve from the configuration.

  ## Examples
      iex> Arca.Config.Cfg.put!("database.host", "localhost")
      "localhost"
      iex> Arca.Config.Cfg.get!("database.host")
      "localhost"

  ## Raises
    - `RuntimeError`: If the key is not found in the configuration.
  """
  @spec get!(String.t() | atom()) :: any() | no_return()
  def get!(key), do: Server.get!(key)

  @doc """
  Updates a value in the configuration and returns `{:ok, value}` or `{:error, reason}`.

  Delegates to `Arca.Config.Server.put/2`, the one write path, so the value is
  persisted, the cache is refreshed and subscribers are notified -- all three, as
  they are for any other write.

  This used to be a second nested write: load from disk, update, write back, and
  tell nobody. The running server's in-memory configuration and the ETS cache
  both stayed on the old value until the file watcher happened to notice the
  file had changed, and a per-key subscriber never heard at all.

  ## Parameters
    - `key`: The key to update in the configuration.
    - `value`: The new value to set for the key.

  ## Examples
      iex> Arca.Config.Cfg.put("database.host", "127.0.0.1")
      {:ok, "127.0.0.1"}
  """
  @spec put(String.t() | atom(), any()) :: {:ok, any()} | {:error, String.t()}
  def put(key, value), do: Server.put(key, value)

  @doc """
  Updates a value in the configuration and raises an error if the operation fails.

  ## Parameters
    - `key`: The key to update in the configuration.
    - `value`: The new value to set for the key.

  ## Examples
      iex> Arca.Config.Cfg.put!("database.host", "127.0.0.1")
      "127.0.0.1"

  ## Raises
    - `RuntimeError`: If the update operation fails.
  """
  @spec put!(String.t() | atom(), any()) :: any() | no_return()
  def put!(key, value), do: Server.put!(key, value)

  @doc """
  Returns the default configuration path based on the config domain name.

  For example, if the config domain is `:my_app`, the default path will be `.my_app/`.
  This can be overridden with the `:default_config_path` config option.

  This path is within the current working directory.
  """
  def default_config_path do
    app_name = config_domain() |> to_string()
    default = ".#{app_name}/"

    Application.get_env(:arca_config, :default_config_path, default)
  end

  @doc """
  Returns the local configuration path based on the config domain name.

  For example, if the config domain is `:my_app`, the local path will be `.my_app/`.
  This can be overridden with the `:local_config_path` config option.

  This path is within the current working directory.
  """
  def local_config_path do
    app_name = config_domain() |> to_string()
    default = ".#{app_name}/"

    Application.get_env(:arca_config, :local_config_path, default)
  end

  @doc """
  Returns the default configuration filename.

  The default is "config.json" but this can be overridden with the 
  `:default_config_file` config option.
  """
  def default_config_file do
    Application.get_env(:arca_config, :default_config_file, "config.json")
  end
end
