defmodule Arca.Config.PhaseBasedTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  setup do
    # Store original environment variables
    original_env = %{
      test_app_path: System.get_env("TEST_APP_CONFIG_PATH"),
      test_app_file: System.get_env("TEST_APP_CONFIG_FILE"),
      arca_path: System.get_env("ARCA_CONFIG_PATH"),
      arca_file: System.get_env("ARCA_CONFIG_FILE")
    }

    # Clean up any existing environment variables
    System.delete_env("TEST_APP_CONFIG_PATH")
    System.delete_env("TEST_APP_CONFIG_FILE")
    System.delete_env("ARCA_CONFIG_PATH")
    System.delete_env("ARCA_CONFIG_FILE")

    # Clean up application config
    Application.delete_env(:arca_config, :config_domain)

    # Reset FileWatcher to dormant state
    send(Arca.Config.FileWatcher, {:reset_to_dormant, self()})

    on_exit(fn ->
      # Restore original environment variables (delete when originally unset).
      for {key, value} <- original_env do
        Arca.Config.Test.Support.restore_env(env_var_for(key), value)
      end

      Application.delete_env(:arca_config, :config_domain)
      # Reset FileWatcher to dormant state after test
      send(Arca.Config.FileWatcher, {:reset_to_dormant, self()})
    end)
  end

  # Map a captured-env key to its environment variable name (pattern-matched,
  # so the on_exit restore stays free of case/if -- IN-EX-TEST-005).
  defp env_var_for(:test_app_path), do: "TEST_APP_CONFIG_PATH"
  defp env_var_for(:test_app_file), do: "TEST_APP_CONFIG_FILE"
  defp env_var_for(:arca_path), do: "ARCA_CONFIG_PATH"
  defp env_var_for(:arca_file), do: "ARCA_CONFIG_FILE"

  test "load_config_phase/0 loads configuration and starts file watching" do
    # Create test config file
    test_path = System.tmp_dir!()
    test_file = "phase_test.json"
    full_path = Path.join(test_path, test_file)

    # Write test config
    File.write!(full_path, Jason.encode!(%{"test_key" => "test_value"}))

    # Set environment for test
    System.put_env("TEST_APP_CONFIG_PATH", test_path)
    System.put_env("TEST_APP_CONFIG_FILE", test_file)

    # Simulate application setting config domain before phase
    Application.put_env(:arca_config, :config_domain, :test_app)

    try do
      # Load configuration during phase
      assert :ok = Arca.Config.load_config_phase()

      # Configuration should be accessible
      assert {:ok, "test_value"} = Arca.Config.get("test_key")

      # FileWatcher should be active (can verify by checking state)
      file_watcher_state = :sys.get_state(Arca.Config.FileWatcher)
      assert file_watcher_state.watching == true
    after
      # Clean up
      File.rm(full_path)
      System.delete_env("TEST_APP_CONFIG_PATH")
      System.delete_env("TEST_APP_CONFIG_FILE")
    end
  end

  test "system loads config from environment-specified paths" do
    # Create test config file with unique name to avoid conflicts
    test_id = :rand.uniform(10000)
    test_path = Path.join(System.tmp_dir!(), "arca_phase_test_#{test_id}")
    File.mkdir_p!(test_path)
    test_file = "config.json"
    full_path = Path.join(test_path, test_file)

    # Write test config with unique value
    unique_value = "test_value_#{test_id}"
    File.write!(full_path, Jason.encode!(%{"test_key" => unique_value}))

    # Use the standard ARCA_CONFIG environment variables
    System.put_env("ARCA_CONFIG_PATH", test_path)
    System.put_env("ARCA_CONFIG_FILE", test_file)

    try do
      # Force server to reload config from the new path
      GenServer.call(Arca.Config.Server, :reload)

      # Config should be loaded from our test file
      assert {:ok, ^unique_value} = Arca.Config.get("test_key")
    after
      # Clean up
      File.rm_rf!(test_path)
      System.delete_env("ARCA_CONFIG_PATH")
      System.delete_env("ARCA_CONFIG_FILE")
    end
  end

  # AT-01.5 (ST0002 acceptance.md). AF-03: apply_env_overrides/0 discarded every
  # put/2 result, so an override that could not be persisted vanished and
  # load_config_phase/0 still reported :ok. The config file here is readable but
  # unwritable, so the load succeeds and only the override write fails.
  test "failed override surfaces from load_config_phase" do
    test_path = Path.join(System.tmp_dir!(), "arca_phase_override_#{:rand.uniform(10_000)}")
    File.mkdir_p!(test_path)
    test_file = "phase_override.json"
    full_path = Path.join(test_path, test_file)

    File.write!(full_path, Jason.encode!(%{"database" => %{"host" => "localhost"}}))
    File.chmod!(full_path, 0o444)

    System.put_env("TEST_APP_CONFIG_PATH", test_path)
    System.put_env("TEST_APP_CONFIG_FILE", test_file)
    System.put_env("TEST_APP_CONFIG_OVERRIDE_DATABASE_PORT", "5432")
    Application.put_env(:arca_config, :config_domain, :test_app)

    on_exit(fn ->
      System.delete_env("TEST_APP_CONFIG_PATH")
      System.delete_env("TEST_APP_CONFIG_FILE")
      System.delete_env("TEST_APP_CONFIG_OVERRIDE_DATABASE_PORT")
      File.chmod(full_path, 0o644)
      File.rm_rf!(test_path)
    end)

    log =
      capture_log(fn ->
        assert {:error, {:env_overrides_failed, [{"database.port", :eacces}]}} =
                 Arca.Config.load_config_phase()
      end)

    assert log =~ "Failed to write config file"
  end

  test "environment overrides are applied during phase loading" do
    # Create test config file
    test_path = System.tmp_dir!()
    test_file = "phase_test3.json"
    full_path = Path.join(test_path, test_file)

    # Write test config
    File.write!(full_path, Jason.encode!(%{"database" => %{"host" => "localhost"}}))

    # Set environment for test
    System.put_env("TEST_APP_CONFIG_PATH", test_path)
    System.put_env("TEST_APP_CONFIG_FILE", test_file)

    Application.put_env(:arca_config, :config_domain, :test_app)

    try do
      # Set environment override
      System.put_env("TEST_APP_CONFIG_OVERRIDE_DATABASE_PORT", "5432")

      # Load configuration during phase
      assert :ok = Arca.Config.load_config_phase()

      # Override should be applied
      assert {:ok, 5432} = Arca.Config.get("database.port")
      assert {:ok, "localhost"} = Arca.Config.get("database.host")
    after
      # Clean up
      File.rm(full_path)
      System.delete_env("TEST_APP_CONFIG_PATH")
      System.delete_env("TEST_APP_CONFIG_FILE")
      System.delete_env("TEST_APP_CONFIG_OVERRIDE_DATABASE_PORT")
    end
  end
end
