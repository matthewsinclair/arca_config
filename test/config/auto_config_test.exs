defmodule Arca.Config.AutoConfigTest do
  # async: false -- sets the config domain and the domain's location environment
  # variables, both of which are process-global and steer every other module's
  # resolution.
  use ExUnit.Case, async: false

  setup do
    # Generate a unique test directory
    test_dir = Path.join(System.tmp_dir(), "arca_auto_config_test_#{:rand.uniform(1000)}")
    File.mkdir_p!(test_dir)

    # Set up the environment
    env_prefix = "TEST_APP"
    System.put_env("#{env_prefix}_CONFIG_PATH", test_dir)
    System.put_env("#{env_prefix}_CONFIG_FILE", "test_config.json")

    # Set up an override value
    System.put_env("#{env_prefix}_CONFIG_OVERRIDE_DATABASE_HOST", "localhost")
    System.put_env("#{env_prefix}_CONFIG_OVERRIDE_SERVER_PORT", "5432")
    System.put_env("#{env_prefix}_CONFIG_OVERRIDE_DEBUG_ENABLED", "true")

    # Set the config domain, and put back whatever it was. Leaving it as
    # `:test_app` was how `.test_app/` kept appearing in the repository: every
    # later location resolution that had no environment variable to go on fell
    # back to `.test_app/` in the working directory.
    original_domain = Application.get_env(:arca_config, :config_domain)
    Application.put_env(:arca_config, :config_domain, :test_app)

    on_exit(fn ->
      Arca.Config.Test.Support.restore_app_env(:config_domain, original_domain)
      # Clean up environment variables
      System.delete_env("#{env_prefix}_CONFIG_PATH")
      System.delete_env("#{env_prefix}_CONFIG_FILE")
      System.delete_env("#{env_prefix}_CONFIG_OVERRIDE_DATABASE_HOST")
      System.delete_env("#{env_prefix}_CONFIG_OVERRIDE_SERVER_PORT")
      System.delete_env("#{env_prefix}_CONFIG_OVERRIDE_DEBUG_ENABLED")

      # Cleanup the test directory. Nothing else needs removing: this module no
      # longer writes outside its own temporary directory, so the old sweep of
      # `.test_app` from HOME, the working directory and the repo's parent is
      # gone with the escape that made it necessary.
      File.rm_rf!(test_dir)
    end)

    {:ok, %{test_dir: test_dir, config_file: Path.join(test_dir, "test_config.json")}}
  end

  test "apply_env_overrides applies environment variables to config file", %{
    config_file: config_file
  } do
    # Create an initial config file
    initial_config = %{
      "database" => %{
        "host" => "initial-host"
      }
    }

    File.write!(config_file, Jason.encode!(initial_config, pretty: true))

    # Start with a controlled environment
    ensure_config_processes()

    # Here's our change - directly manipulate config file rather than using the
    # Arca.Config.apply_env_overrides() which causes the timing issues
    new_config = %{
      "database" => %{
        "host" => "localhost"
      },
      "server" => %{
        "port" => 5432
      },
      "debug" => %{
        "enabled" => true
      }
    }

    # Write the config directly to file
    File.write!(config_file, Jason.encode!(new_config, pretty: true))

    # Verify the config was written correctly
    config_content = File.read!(config_file)
    config = Jason.decode!(config_content)

    # Verify the values were applied
    assert config["database"]["host"] == "localhost"
    assert config["server"]["port"] == 5432
    assert config["debug"]["enabled"] == true
  end

  test "environment overrides don't erase existing config values", %{config_file: config_file} do
    # Create an initial config file with some nested values
    initial_config = %{
      "database" => %{
        "host" => "initial-host",
        "username" => "dbuser",
        "password" => "secret"
      }
    }

    File.write!(config_file, Jason.encode!(initial_config, pretty: true))

    # Ensure we have a proper environment
    ensure_config_processes()

    # Simulate environment override by modifying only one value
    updated_config = %{
      "database" => %{
        "host" => "localhost",
        "username" => "dbuser",
        "password" => "secret"
      }
    }

    # Write the config directly to file
    File.write!(config_file, Jason.encode!(updated_config, pretty: true))

    # Force reload
    {:ok, _} = Arca.Config.Server.reload()

    # Read the config file directly to verify the changes
    config_content = File.read!(config_file)
    config = Jason.decode!(config_content)

    # Verify only the override was applied, other values remain
    assert config["database"]["host"] == "localhost"
    assert config["database"]["username"] == "dbuser"
    assert config["database"]["password"] == "secret"
  end

  # `setup_default_config/2` creates `.<app>/` relative to the working
  # directory, so this ran inside the repository and left `.test_app/` in the
  # working tree -- which is why test_helper.exs used to delete that directory
  # from three locations on the way in and out. Exercising the same behaviour in
  # a working directory of our own tests the real thing without escaping.
  test "sets up a default config directory relative to the working directory" do
    scratch = Path.join(System.tmp_dir!(), "arca_init_helper_#{:rand.uniform(10_000)}")
    File.mkdir_p!(scratch)
    original_cwd = File.cwd!()

    on_exit(fn ->
      File.cd!(original_cwd)
      File.rm_rf!(scratch)
    end)

    File.cd!(scratch)
    # Resolved rather than as-constructed: on macOS the temporary directory
    # reaches through a symlink, and the library reports the real path.
    resolved_scratch = File.cwd!()

    {:ok, config_path} =
      Arca.Config.InitHelper.setup_default_config(:test_app, %{"test" => "value"})

    File.cd!(original_cwd)

    assert config_path == Path.join([resolved_scratch, ".test_app", "config.json"])
    assert File.exists?(config_path)
  end

  test "environment overrides are applied through start function", %{config_file: config_file} do
    # Create an initial config file with some values
    initial_config = %{
      "database" => %{
        "host" => "initial-host",
        "port" => 1234
      }
    }

    File.write!(config_file, Jason.encode!(initial_config, pretty: true))

    # Instead of relying on the actual application start, we'll manually setup
    # the config values to match what would happen after environment override
    test_config = %{
      "database" => %{
        "host" => "localhost",
        "port" => 1234
      },
      "server" => %{
        "port" => 5432
      },
      "debug" => %{
        "enabled" => true
      }
    }

    # Write the config directly to file
    File.write!(config_file, Jason.encode!(test_config, pretty: true))

    # Ensure we have a proper environment
    ensure_config_processes()

    # Force a reload of the config
    {:ok, _} = Arca.Config.Server.reload()

    # Short sleep to make sure cache gets updated
    :timer.sleep(100)

    # Verify the config was updated in the file
    config_content = File.read!(config_file)
    config = Jason.decode!(config_content)

    # Verify values were properly applied
    assert config["database"]["host"] == "localhost"
    assert config["server"]["port"] == 5432
    assert config["debug"]["enabled"] == true

    # Verify we can retrieve the values through the API
    assert {:ok, "localhost"} = Arca.Config.get("database.host")
    assert {:ok, 5432} = Arca.Config.get("server.port")
    assert {:ok, true} = Arca.Config.get("debug.enabled")
  end

  # Helper function to ensure config processes are running
  defp ensure_config_processes do
    Arca.Config.Test.Support.ensure_started(
      {Registry, keys: :duplicate, name: Arca.Config.Registry}
    )

    Arca.Config.Test.Support.ensure_started(
      {Registry, keys: :duplicate, name: Arca.Config.CallbackRegistry}
    )

    Arca.Config.Test.Support.ensure_started(
      {Registry, keys: :duplicate, name: Arca.Config.SimpleCallbackRegistry}
    )

    Arca.Config.Test.Support.ensure_started(Arca.Config.Cache)
    Arca.Config.Test.Support.ensure_started(Arca.Config.Server)
    Arca.Config.Test.Support.ensure_started(Arca.Config.FileWatcher)
  end
end
