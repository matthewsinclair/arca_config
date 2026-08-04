defmodule Arca.Config.SwitchLocationTest do
  # async: false -- switching the config location rewrites the location
  # environment variables for the whole VM, which is the mechanism under test.
  use ExUnit.Case, async: false

  alias Arca.Config
  alias Arca.Config.Cache

  setup do
    # Store original environment variables
    app_name = Arca.Config.Cfg.config_domain() |> to_string()
    app_specific_path_var = "#{String.upcase(app_name)}_CONFIG_PATH"
    app_specific_file_var = "#{String.upcase(app_name)}_CONFIG_FILE"

    original_env = %{
      app_specific_path: System.get_env(app_specific_path_var),
      app_specific_file: System.get_env(app_specific_file_var)
    }

    # Create test directories for different config locations
    test_base_dir = Path.join(System.tmp_dir(), "arca_switch_test_#{:rand.uniform(10000)}")
    location1_dir = Path.join(test_base_dir, "location1")
    location2_dir = Path.join(test_base_dir, "location2")
    location3_dir = Path.join(test_base_dir, "location3")

    File.mkdir_p!(location1_dir)
    File.mkdir_p!(location2_dir)
    File.mkdir_p!(location3_dir)

    # Create different config files in each location
    config1 = %{
      "location" => "one",
      "app" => %{
        "name" => "App1",
        "version" => "1.0.0"
      },
      "database" => %{
        "host" => "db1.example.com"
      }
    }

    config2 = %{
      "location" => "two",
      "app" => %{
        "name" => "App2",
        "version" => "2.0.0"
      },
      "database" => %{
        "host" => "db2.example.com"
      }
    }

    config3 = %{
      "location" => "three",
      "app" => %{
        "name" => "App3",
        "version" => "3.0.0"
      },
      "server" => %{
        "port" => 8080
      }
    }

    File.write!(Path.join(location1_dir, "config.json"), Jason.encode!(config1, pretty: true))
    File.write!(Path.join(location2_dir, "settings.json"), Jason.encode!(config2, pretty: true))
    File.write!(Path.join(location3_dir, "app.json"), Jason.encode!(config3, pretty: true))

    # Ensure necessary processes are started
    start_processes()

    # Set initial config location to location1
    System.put_env(app_specific_path_var, location1_dir)
    System.put_env(app_specific_file_var, "config.json")
    Config.reload()

    on_exit(fn ->
      # Restore original environment variables (delete when originally unset).
      Arca.Config.Test.Support.restore_env(app_specific_path_var, original_env.app_specific_path)
      Arca.Config.Test.Support.restore_env(app_specific_file_var, original_env.app_specific_file)

      # Clean up test directories
      File.rm_rf!(test_base_dir)
    end)

    %{
      location1_dir: location1_dir,
      location2_dir: location2_dir,
      location3_dir: location3_dir,
      config1: config1,
      config2: config2,
      config3: config3,
      app_specific_path_var: app_specific_path_var,
      app_specific_file_var: app_specific_file_var
    }
  end

  describe "switch_config_location/1" do
    test "switches to a new config location", %{location2_dir: location2_dir} do
      # Initial state should be from location1
      assert {:ok, "one"} = Config.get("location")
      assert {:ok, "App1"} = Config.get("app.name")

      # Switch to location2
      {:ok, _previous} =
        Config.switch_config_location(
          path: location2_dir,
          file: "settings.json"
        )

      # Should now read from location2
      assert {:ok, "two"} = Config.get("location")
      assert {:ok, "App2"} = Config.get("app.name")
      assert {:ok, "db2.example.com"} = Config.get("database.host")
    end

    test "returns previous location for restoration", %{
      location1_dir: location1_dir,
      location2_dir: location2_dir
    } do
      # Switch to location2
      {:ok, previous} =
        Config.switch_config_location(
          path: location2_dir,
          file: "settings.json"
        )

      # Previous location should contain original settings
      assert previous[:path] == location1_dir
      assert previous[:file] == "config.json"

      # Restore previous location
      {:ok, _} = Config.switch_config_location(previous)

      # Should be back to location1
      assert {:ok, "one"} = Config.get("location")
      assert {:ok, "App1"} = Config.get("app.name")
    end

    test "clears cache when switching locations", %{location2_dir: location2_dir} do
      # Load a value to ensure it's cached
      assert {:ok, "one"} = Config.get("location")

      # Value should be in cache
      assert {:ok, "one"} = Cache.get(["location"])

      # Switch location
      {:ok, _} =
        Config.switch_config_location(
          path: location2_dir,
          file: "settings.json"
        )

      # Cache should have new value
      assert {:ok, "two"} = Cache.get(["location"])
    end

    test "file watcher monitors new location after switch", %{
      location2_dir: location2_dir
    } do
      # Switch to location2
      {:ok, _} =
        Config.switch_config_location(
          path: location2_dir,
          file: "settings.json"
        )

      # Verify initial state
      assert {:ok, "two"} = Config.get("location")

      # Modify the config file in location2
      config_path = Path.join(location2_dir, "settings.json")

      updated_config = %{
        "location" => "two-modified",
        "app" => %{"name" => "App2-Updated"}
      }

      File.write!(config_path, Jason.encode!(updated_config, pretty: true))

      # Instead of waiting for file watcher, manually trigger a reload
      # This tests that the new location is being used
      {:ok, _} = Config.reload()

      # Should now have the updated value
      assert {:ok, "two-modified"} = Config.get("location")
      assert {:ok, "App2-Updated"} = Config.get("app.name")
    end

    test "handles switch with only path change", %{location2_dir: location2_dir} do
      # The filename is retained across a path-only switch, so location2 needs a
      # config.json of its own to switch into.
      File.write!(
        Path.join(location2_dir, "config.json"),
        Jason.encode!(%{"location" => "two-via-config-json"}, pretty: true)
      )

      # Switch with only path (should use same filename)
      {:ok, previous} = Config.switch_config_location(path: location2_dir)

      assert {:ok, "two-via-config-json"} = Config.get("location")

      # Restore
      Config.switch_config_location(previous)
      assert {:ok, "one"} = Config.get("location")
    end

    test "handles switch with only file change", %{location1_dir: location1_dir} do
      # Create another config file in location1
      alt_config = %{"alt" => true, "location" => "alt"}

      File.write!(
        Path.join(location1_dir, "alt.json"),
        Jason.encode!(alt_config, pretty: true)
      )

      # Switch with only file (should use same path)
      {:ok, _previous} = Config.switch_config_location(file: "alt.json")

      # Should read from alt.json in location1
      assert {:ok, "alt"} = Config.get("location")
      assert {:ok, true} = Config.get("alt")
    end

    # AT-01.6 (ST0002 acceptance.md), ruling R4. Replaces a test that asserted
    # AF-06: a switch to a nonexistent path used to succeed with an empty config
    # (enoent read as "empty"), and the comments narrated the drift.
    test "switch to nonexistent path errors and preserves location", %{
      location1_dir: location1_dir,
      app_specific_path_var: app_specific_path_var,
      app_specific_file_var: app_specific_file_var
    } do
      assert {:error, reason} =
               Config.switch_config_location(
                 path: "/non/existent/path",
                 file: "config.json"
               )

      assert reason == {:config, :load_failed, :enoent}

      # The previous location stays live: config, cache and env vars all intact.
      assert {:ok, "one"} = Config.get("location")
      assert {:ok, "App1"} = Config.get("app.name")
      assert System.get_env(app_specific_path_var) == location1_dir
      assert System.get_env(app_specific_file_var) == "config.json"
    end

    test "multiple switches work correctly", %{
      location2_dir: location2_dir,
      location3_dir: location3_dir
    } do
      # Initial state
      assert {:ok, "one"} = Config.get("location")

      # Switch to location2
      {:ok, _} =
        Config.switch_config_location(
          path: location2_dir,
          file: "settings.json"
        )

      assert {:ok, "two"} = Config.get("location")

      # Switch to location3
      {:ok, _} =
        Config.switch_config_location(
          path: location3_dir,
          file: "app.json"
        )

      assert {:ok, "three"} = Config.get("location")
      assert {:ok, 8080} = Config.get("server.port")

      # Verify location2 specific keys don't exist
      assert {:error, _} = Config.get("database.host")
    end

    test "callbacks are notified on location switch", %{location2_dir: location2_dir} do
      # Notify this process from the callback so we can await it synchronously.
      test_pid = self()
      callback_fn = fn -> send(test_pid, :callback_invoked) end

      {:ok, ref} = Config.add_callback(callback_fn)

      # Switch location
      {:ok, _} =
        Config.switch_config_location(
          path: location2_dir,
          file: "settings.json"
        )

      # Await the callback instead of sleeping.
      assert_receive :callback_invoked, 1000

      # Clean up
      Config.remove_callback(ref)
    end

    test "environment variables are properly updated", %{
      location2_dir: location2_dir,
      app_specific_path_var: app_specific_path_var,
      app_specific_file_var: app_specific_file_var
    } do
      # Switch location
      {:ok, _} =
        Config.switch_config_location(
          path: location2_dir,
          file: "settings.json"
        )

      # Check environment variables
      assert System.get_env(app_specific_path_var) == location2_dir
      assert System.get_env(app_specific_file_var) == "settings.json"
    end

    test "can clear config location with nil values", %{
      location3_dir: location3_dir,
      app_specific_path_var: app_specific_path_var,
      app_specific_file_var: app_specific_file_var
    } do
      # Store current values
      current_path = System.get_env(app_specific_path_var)
      current_file = System.get_env(app_specific_file_var)
      original_generic_path = System.get_env("ARCA_CONFIG_PATH")
      original_generic_file = System.get_env("ARCA_CONFIG_FILE")

      # Clearing the app-specific pair falls through to the generic pair, so
      # point that at a location which actually holds a config file: under
      # ruling R4 a switch to a location with no config file now fails.
      System.put_env("ARCA_CONFIG_PATH", location3_dir)
      System.put_env("ARCA_CONFIG_FILE", "app.json")

      on_exit(fn ->
        Arca.Config.Test.Support.restore_env("ARCA_CONFIG_PATH", original_generic_path)
        Arca.Config.Test.Support.restore_env("ARCA_CONFIG_FILE", original_generic_file)
      end)

      # Clear with nil
      {:ok, previous} =
        Config.switch_config_location(
          path: nil,
          file: nil
        )

      # Environment variables should be cleared
      assert System.get_env(app_specific_path_var) == nil
      assert System.get_env(app_specific_file_var) == nil

      # ... and resolution fell through to the generic pair
      assert {:ok, "three"} = Config.get("location")

      # Restore
      Config.switch_config_location(previous)
      assert System.get_env(app_specific_path_var) == current_path
      assert System.get_env(app_specific_file_var) == current_file
    end
  end

  # Every process this module needs, started the one way. Three of these were
  # `try do Registry.start_link(...) rescue _ -> :ok end` -- the same
  # rescue-fabricates-success defect this thread removed from `Cache` (see
  # `cache.ex`), surviving in a test file. `Registry.start_link/1` on an
  # already-registered name *returns* `{:error, {:already_started, pid}}`; it
  # does not raise, so the rescue never fired for the case it claimed to cover,
  # and when the start did succeed it linked the registry to the test process
  # instead of the test supervisor.
  defp start_processes do
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

    :ok
  end
end
