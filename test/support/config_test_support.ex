defmodule Arca.Config.Test.Support do
  @moduledoc """
  Support functions for testing Arca.Config
  """

  @doc """
  Write a default config file for testing
  """
  def write_default_config_file(config_file \\ nil, config_path \\ nil) do
    # Save original env vars
    original_file = System.get_env("ARCA_CONFIG_FILE")
    original_path = System.get_env("ARCA_CONFIG_PATH")

    # Set test env vars
    if config_file, do: System.put_env("ARCA_CONFIG_FILE", config_file)
    if config_path, do: System.put_env("ARCA_CONFIG_PATH", config_path)

    config_path = config_path || System.tmp_dir!()
    config_file = config_file || "config_test.json"
    full_path = Path.join(config_path, config_file)

    # Ensure directory exists
    File.mkdir_p!(Path.dirname(Path.expand(full_path)))

    # Write test config
    File.write!(
      Path.expand(full_path),
      ~s({"id": "DOT_SLASH_DOT_LL_SLASH_CONFIG_DOT_JSON", "database": {"host": "localhost"}})
    )

    # Register cleanup
    on_exit = Process.get(:on_exit) || fn -> :ok end
    old_on_exit = on_exit

    Process.put(:on_exit, fn ->
      # Clean up test file
      File.rm(Path.expand(full_path))

      # Restore original env vars or delete if they weren't set
      if original_file,
        do: System.put_env("ARCA_CONFIG_FILE", original_file),
        else: System.delete_env("ARCA_CONFIG_FILE")

      if original_path,
        do: System.put_env("ARCA_CONFIG_PATH", original_path),
        else: System.delete_env("ARCA_CONFIG_PATH")

      # Call original cleanup
      old_on_exit.()
    end)

    # Return path for reference
    full_path
  end

  @doc """
  Helper to clean up after tests
  """
  def on_exit(fun) do
    ExUnit.Callbacks.on_exit(fun)
  end

  @doc """
  Restore an environment variable to a captured value, deleting it when it was
  originally unset. Pattern-matched so test setup/on_exit avoid if/else
  (IN-EX-TEST-005).
  """
  def restore_env(var, nil), do: System.delete_env(var)
  def restore_env(var, value), do: System.put_env(var, value)

  @doc """
  Restore an `:arca_config` application setting to a captured value, deleting it
  when it was originally unset. Pattern-matched so callers avoid if/else.
  """
  def restore_app_env(key, nil), do: Application.delete_env(:arca_config, key)
  def restore_app_env(key, value), do: Application.put_env(:arca_config, key, value)

  @doc """
  Ensure a process is running under the test supervisor, tolerating an instance
  the application already owns. Keeps test setup straight-line.
  """
  def ensure_started(child_spec) do
    child_spec |> ExUnit.Callbacks.start_supervised() |> handle_started()
  end

  defp handle_started({:ok, _pid}), do: :ok
  defp handle_started({:error, {:already_started, _pid}}), do: :ok
  defp handle_started({:error, {{:already_started, _pid}, _spec}}), do: :ok
end
