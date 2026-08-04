defmodule Arca.Config.ServerTest do
  # async: false -- exercises the single named configuration server against one
  # on-disk file, and switches the config domain inside one describe block.
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias Arca.Config.Cache
  alias Arca.Config.Server

  setup do
    # Store original environment variables
    app_name = Arca.Config.Cfg.config_domain() |> to_string()
    app_specific_path_var = "#{String.upcase(app_name)}_CONFIG_PATH"
    app_specific_file_var = "#{String.upcase(app_name)}_CONFIG_FILE"

    original_env = %{
      app_specific_path: System.get_env(app_specific_path_var),
      app_specific_file: System.get_env(app_specific_file_var),
      config_path: System.get_env("ARCA_CONFIG_PATH"),
      config_file: System.get_env("ARCA_CONFIG_FILE")
    }

    # Set up test config file
    test_dir = Path.join(System.tmp_dir(), "arca_config_test_#{:rand.uniform(1000)}")
    File.mkdir_p!(test_dir)
    test_file = Path.join(test_dir, "test_config.json")

    # Set environment variables for test - use app-specific variables since they take precedence
    System.put_env(app_specific_path_var, test_dir)
    System.put_env(app_specific_file_var, "test_config.json")

    # Write initial test config
    File.write!(
      test_file,
      Jason.encode!(
        %{
          "app" => %{
            "name" => "TestApp",
            "version" => "1.0.0"
          },
          "database" => %{
            "host" => "localhost",
            "port" => 5432
          }
        },
        pretty: true
      )
    )

    # Ensure the registry and servers are running (tolerating app-owned instances).
    Arca.Config.Test.Support.ensure_started(
      {Registry, keys: :duplicate, name: Arca.Config.Registry}
    )

    Arca.Config.Test.Support.ensure_started(Arca.Config.Cache)
    Arca.Config.Test.Support.ensure_started(Arca.Config.Server)

    # Reload the server with new config
    Server.reload()

    on_exit(fn ->
      # Restore original environment variables (delete when originally unset).
      Arca.Config.Test.Support.restore_env(app_specific_path_var, original_env.app_specific_path)
      Arca.Config.Test.Support.restore_env(app_specific_file_var, original_env.app_specific_file)
      Arca.Config.Test.Support.restore_env("ARCA_CONFIG_PATH", original_env.config_path)
      Arca.Config.Test.Support.restore_env("ARCA_CONFIG_FILE", original_env.config_file)

      # Clean up test directory
      File.rm_rf!(test_dir)
    end)

    {:ok, %{test_dir: test_dir, test_file: test_file}}
  end

  describe "get/1" do
    test "retrieves a value by string key" do
      assert {:ok, "TestApp"} = Server.get("app.name")
    end

    test "retrieves a value by atom key" do
      assert {:ok, "TestApp"} = Server.get(:"app.name")
    end

    test "retrieves a value by list key" do
      assert {:ok, "TestApp"} = Server.get(["app", "name"])
    end

    test "returns error for non-existent key" do
      assert {:error, _} = Server.get("non.existent")
    end

    test "retrieves nested maps" do
      assert {:ok, %{"host" => "localhost", "port" => 5432}} = Server.get("database")
    end
  end

  describe "get!/1" do
    test "retrieves a value by key" do
      assert "TestApp" = Server.get!("app.name")
    end

    test "raises for non-existent key" do
      assert_raise RuntimeError, fn -> Server.get!("non.existent") end
    end
  end

  describe "put/2" do
    test "updates an existing value" do
      assert {:ok, "NewApp"} = Server.put("app.name", "NewApp")
      assert {:ok, "NewApp"} = Server.get("app.name")
    end

    test "creates a new nested value" do
      assert {:ok, "production"} = Server.put("app.environment", "production")
      assert {:ok, "production"} = Server.get("app.environment")
    end

    test "creates a deeply nested value" do
      assert {:ok, "admin"} = Server.put(["database", "user", "name"], "admin")
      assert {:ok, "admin"} = Server.get(["database", "user", "name"])
      assert {:ok, %{"name" => "admin"}} = Server.get(["database", "user"])
    end

    setup do
      # Set up a dedicated test directory for the absolute path tests
      test_name = "absolute_path_test_#{:rand.uniform(1000)}"
      test_dir = Path.join(System.tmp_dir(), test_name) |> Path.expand()
      File.mkdir_p!(test_dir)

      # Get the environment variables we'll be modifying
      app_name = Arca.Config.Cfg.config_domain() |> to_string()
      app_specific_path_var = "#{String.upcase(app_name)}_CONFIG_PATH"
      app_specific_file_var = "#{String.upcase(app_name)}_CONFIG_FILE"

      # Save original environment variables and application settings
      original_path_env = System.get_env(app_specific_path_var)
      original_file_env = System.get_env(app_specific_file_var)
      original_config_path = Application.get_env(:arca_config, :config_path)
      original_config_file = Application.get_env(:arca_config, :config_file)
      original_domain = Application.get_env(:arca_config, :config_domain)

      # Switching the domain changes which environment variables are consulted,
      # so point the new domain at this block's temporary directory. Without
      # that, resolution fell through to the lowest tier -- `.test_app/`
      # relative to the working directory -- and these tests wrote into the
      # repository.
      original_test_app_path = System.get_env("TEST_APP_CONFIG_PATH")
      original_test_app_file = System.get_env("TEST_APP_CONFIG_FILE")

      Application.put_env(:arca_config, :config_domain, :test_app)
      System.put_env("TEST_APP_CONFIG_PATH", test_dir)
      System.put_env("TEST_APP_CONFIG_FILE", "test_config.json")

      on_exit(fn ->
        Arca.Config.Test.Support.restore_env("TEST_APP_CONFIG_PATH", original_test_app_path)
        Arca.Config.Test.Support.restore_env("TEST_APP_CONFIG_FILE", original_test_app_file)

        # Restore original environment variables (delete when originally unset).
        Arca.Config.Test.Support.restore_env(app_specific_path_var, original_path_env)
        Arca.Config.Test.Support.restore_env(app_specific_file_var, original_file_env)

        # Restore original application settings (delete when originally unset).
        Arca.Config.Test.Support.restore_app_env(:config_path, original_config_path)
        Arca.Config.Test.Support.restore_app_env(:config_file, original_config_file)
        Arca.Config.Test.Support.restore_app_env(:config_domain, original_domain)

        # Clean up test directories
        File.rm_rf!(test_dir)
      end)

      {:ok,
       %{
         test_dir: test_dir,
         app_specific_path_var: app_specific_path_var,
         app_specific_file_var: app_specific_file_var
       }}
    end

    test "correctly handles absolute paths when writing config", %{
      test_dir: test_dir
      # Unused setup variables
      # app_specific_path_var: _app_specific_path_var,
      # app_specific_file_var: _app_specific_file_var
    } do
      # Create a special absolute path for this test directly within the test_dir
      absolute_path = Path.join(test_dir, "absolute_dir") |> Path.expand()
      # Debug output suppressed
      File.mkdir_p!(absolute_path)

      # VERY IMPORTANT: We will use a direct method where we override the important functions
      # Create a test module that will allow us to hook into the path resolution

      # Create a direct file and write to it
      config_file = Path.join(absolute_path, "absolute_test.json")

      # Force a reload to pick up new config location
      Server.reload()

      # Point the location at the absolute path. This used to set application
      # config, which is the third tier and was shadowed the moment this block
      # started setting the domain's own environment variables.
      System.put_env("TEST_APP_CONFIG_PATH", absolute_path)
      System.put_env("TEST_APP_CONFIG_FILE", "absolute_test.json")

      # Write initial content to the file and make sure directory exists
      File.mkdir_p!(absolute_path)
      File.write!(config_file, "{}")
      # Debug output suppressed

      # Directly create a GenServer with our specified paths
      {:ok, _config} = Server.reload()

      # Use the GenServer's put to update the config
      assert {:ok, "test_value"} = Server.put("absolute_path_test", "test_value")

      # Since we're now directly working with the file, we should ensure it exists
      assert File.exists?(config_file),
             "Config file not found at expected location: #{config_file}"

      # Check the content of the file
      # NOTE: We must use our server here, not direct file reading
      assert {:ok, "test_value"} = Server.get("absolute_path_test")

      # Ensure we can read the value back
      assert {:ok, "test_value"} = Server.get("absolute_path_test")
    end

    test "prevents recursive directory creation with absolute paths", %{
      test_dir: test_dir
      # Unused setup variables
      # app_specific_path_var: _app_specific_path_var,
      # app_specific_file_var: _app_specific_file_var
    } do
      # Create a target directory for absolute path testing
      target_dir = Path.join(test_dir, "recursive_test") |> Path.expand()
      File.mkdir_p!(target_dir)

      # Create a local relative directory for the first part of the test
      local_config_dir = Path.join(test_dir, "local_config") |> Path.expand()
      File.mkdir_p!(local_config_dir)

      # Create the config file directly
      local_config_file = Path.join(local_config_dir, "recursive_test.json")
      File.write!(local_config_file, "{}")

      # Force a reload to pick up initial config location
      Server.reload()

      # Write a value to the local path
      assert {:ok, "initial_value"} = Server.put("initial_key", "initial_value")

      # Verify a local config was created
      local_config_file = Path.join(local_config_dir, "recursive_test.json")

      assert File.exists?(local_config_file),
             "Config file not found at expected location: #{local_config_file}"

      # Now switch to absolute path mid-operation (this would have triggered the bug before)
      # Create a direct file in the target directory
      target_config_file = Path.join(target_dir, "recursive_test.json")
      File.write!(target_config_file, "{}")

      # Force a reload to pick up the new location
      Server.reload()

      # Write a second config value - this should use the absolute path
      assert {:ok, "recursive_test_value"} =
               Server.put("recursive_test_key", "recursive_test_value")

      # We've already defined this earlier, no need to redefine

      assert File.exists?(target_config_file),
             "Config file not found at expected location: #{target_config_file}"

      # Check if a recursive directory structure was created (which would be a bug)
      # Test for the problematic path that was previously created: ./path/absolute/path/...
      recursive_path = Path.join([local_config_dir, target_dir])

      refute File.exists?(recursive_path),
             "Recursive directory structure was created at: #{recursive_path}"

      # Check for the most problematic recursive pattern:
      # Current dir + path component of absolute path
      path_components = Path.split(target_dir)
      deep_recursive_path = Path.join([local_config_dir] ++ path_components)

      refute File.exists?(deep_recursive_path),
             "Deep recursive directory structure was created at: #{deep_recursive_path}"
    end
  end

  describe "put!/2" do
    test "updates a value and returns it" do
      assert "NewVersion" = Server.put!("app.version", "NewVersion")
      assert {:ok, "NewVersion"} = Server.get("app.version")
    end
  end

  describe "delete/1" do
    test "deletes a simple top-level key" do
      assert {:ok, :deleted} = Server.delete("app")
      assert {:error, _} = Server.get("app")
      assert {:ok, _} = Server.get("database")
    end

    test "deletes a nested key" do
      assert {:ok, :deleted} = Server.delete("database.port")

      # Parent still exists
      assert {:ok, %{"host" => "localhost"}} = Server.get("database")

      # Deleted key is gone
      assert {:error, _} = Server.get("database.port")
    end

    test "returns success when deleting non-existent key" do
      assert {:ok, :deleted} = Server.delete("non_existent")
      assert {:ok, :deleted} = Server.delete("database.non_existent")
    end

    test "properly invalidates the cache" do
      # First verify the key exists and is cached
      assert {:ok, "TestApp"} = Server.get("app.name")

      # Delete the key
      assert {:ok, :deleted} = Server.delete("app.name")

      # Verify it's gone
      assert {:error, _} = Server.get("app.name")
    end
  end

  describe "delete!/1" do
    test "deletes a key and returns :deleted" do
      assert :deleted = Server.delete!("app.name")
      assert {:error, _} = Server.get("app.name")
    end
  end

  # AT-03.4 (ST0002 acceptance.md). AF-20 / probe P2: a nested put cached only
  # the leaf, so an ancestor read was served the pre-put map from cache while
  # disk already held the new value.
  describe "cache coherence (AR-3)" do
    test "ancestor get reflects nested put (cache coherence)" do
      assert {:ok, %{"host" => "localhost", "port" => 5432}} = Server.get("database")

      assert {:ok, "new-host"} = Server.put("database.host", "new-host")

      assert {:ok, %{"host" => "new-host", "port" => 5432}} = Server.get("database")
    end
  end

  # AT-01.1, AT-01.2 (ST0002 acceptance.md). Reproduces probe P3b: the config
  # file stays readable but unwritable, so the load succeeds and only the
  # persist fails -- the exact shape of AF-01/AF-02.
  describe "persistence failure (AR-1)" do
    setup %{test_file: test_file} do
      File.chmod!(test_file, 0o444)
      on_exit(fn -> File.chmod(test_file, 0o644) end)
      :ok
    end

    test "put returns error and preserves state on unwritable location", %{test_file: test_file} do
      on_disk_before = File.read!(test_file)

      log = capture_log(fn -> assert {:error, :eacces} = Server.put("app.name", "PhantomApp") end)

      assert log =~ "Failed to write config file"
      assert File.read!(test_file) == on_disk_before
      assert {:ok, "TestApp"} = Server.get("app.name")
    end

    test "delete returns error and preserves state on unwritable location", %{
      test_file: test_file
    } do
      on_disk_before = File.read!(test_file)

      log = capture_log(fn -> assert {:error, :eacces} = Server.delete("app.name") end)

      assert log =~ "Failed to write config file"
      assert File.read!(test_file) == on_disk_before
      assert {:ok, "TestApp"} = Server.get("app.name")
    end

    test "put!/delete! raise on persistence failure" do
      capture_log(fn ->
        assert_raise RuntimeError, ~r/eacces/, fn -> Server.put!("app.name", "PhantomApp") end
        assert_raise RuntimeError, ~r/eacces/, fn -> Server.delete!("app.name") end
      end)
    end
  end

  # AT-01.3 (ST0002 acceptance.md). AF-04: an on-demand load failure was marked
  # `loaded: true` with an empty config, so every subsequent key reported
  # "Key not found" and the real cause never reached the caller.
  describe "load failure (AR-1)" do
    setup %{test_file: test_file} do
      File.write!(test_file, "{not json")
      Cache.clear()
      :sys.replace_state(Server, fn _ -> %{config: %{}, loaded: false} end)

      on_exit(fn ->
        File.write!(test_file, Jason.encode!(%{"app" => %{"name" => "TestApp"}}))
        Server.reload()
      end)

      :ok
    end

    test "failed load surfaces as load error not key-miss" do
      assert {:error, reason} = Server.get("app.name")

      assert reason =~ "Error parsing config"
      refute reason == "Key not found"
    end
  end

  describe "reload/0" do
    test "reloads configuration from disk", %{test_file: test_file} do
      # Modify the file directly
      config = %{
        "app" => %{
          "name" => "UpdatedApp",
          "version" => "2.0.0"
        }
      }

      File.write!(test_file, Jason.encode!(config, pretty: true))

      # Reload should pick up the changes
      assert {:ok, reloaded_config} = Server.reload()
      assert reloaded_config["app"]["name"] == "UpdatedApp"
      assert {:ok, "UpdatedApp"} = Server.get("app.name")
    end
  end

  describe "notify_external_change/0" do
    # AT-02.5. `:get_config` replies with one shape: the config map. The clause
    # this pins used to be joined by a `{:ok, conf}` clause that nothing could
    # produce, and the test that covered it mocked GenServer itself to fabricate
    # the reply -- mocking the runtime to reach code the runtime cannot reach.
    # Both are gone; this asserts the real reply through the real server.
    test "dispatches the current config to callbacks and reports notified" do
      test_pid = self()

      Arca.Config.register_change_callback(:test_callback, fn config ->
        send(test_pid, {:callback_received, config})
      end)

      on_exit(fn -> Arca.Config.unregister_change_callback(:test_callback) end)

      assert {:ok, :notified} = Server.notify_external_change()

      assert_receive {:callback_received, config}, 500
      assert %{"app" => %{"name" => "TestApp"}} = config
    end

    test "the :get_config call answers with the config map itself" do
      assert %{"app" => %{"name" => "TestApp"}} =
               GenServer.call(Arca.Config.Server, :get_config)
    end
  end

  describe "subscribe/1 and notifications" do
    setup do
      # Ensure the registry and server are running before subscribing
      # (synchronous start instead of a timing sleep).
      Arca.Config.Test.Support.ensure_started(
        {Registry, keys: :duplicate, name: Arca.Config.Registry}
      )

      Arca.Config.Test.Support.ensure_started(Arca.Config.Server)
      :ok
    end

    test "notifies subscribers when value changes" do
      # Subscribe to the key
      Server.subscribe("app.name")

      # Update the value
      Server.put("app.name", "NotifiedApp")

      # Check for notification
      assert_receive {:config_updated, ["app", "name"], "NotifiedApp"}, 500
    end

    # AT-02.1 (AC-02.1). Every public write reaches the same implementation, so
    # every public write has the same observable consequences: disk, cache and
    # subscribers all move together. `Cfg.put/2` used to be a second nested
    # write that loaded from disk, wrote back to disk, and told nobody -- the
    # server's memory and the ETS cache stayed on the old value until the file
    # watcher happened to notice, and a subscriber never heard at all.
    #
    # The AC's original wording asked for the watcher write-token to be
    # registered exactly once per write path. WP-03 removed the token
    # mechanism outright (a write that changes nothing raises no event, so
    # there is nothing to suppress), so the invariant is stated here as the
    # behaviour the token existed to protect.
    test "a write through Cfg has the same effect as a write through Server" do
      Server.subscribe("app.name")

      assert {:ok, "ViaCfg"} = Arca.Config.Cfg.put("app.name", "ViaCfg")

      assert_receive {:config_updated, ["app", "name"], "ViaCfg"}, 500
      assert {:ok, "ViaCfg"} = Server.get("app.name")
      assert {:ok, "ViaCfg"} = Arca.Config.Cache.get(["app", "name"])
    end

    test "a read through Cfg sees a write made through Server" do
      Server.put("app.name", "WrittenViaServer")

      assert {:ok, "WrittenViaServer"} = Arca.Config.Cfg.get("app.name")
    end

    test "unsubscribe stops notifications" do
      # Subscribe and then unsubscribe
      Server.subscribe("app.version")
      Server.unsubscribe("app.version")

      # Update the value
      Server.put("app.version", "3.0.0")

      # Should not receive notification
      refute_receive {:config_updated, ["app", "version"], "3.0.0"}, 500
    end

    test "parent keys are notified when child changes" do
      # Subscribe to parent
      Server.subscribe("database")

      # Update a child
      Server.put("database.host", "new-host")

      # Should receive notification for database (with updated host)
      assert_receive {:config_updated, ["database"], %{"host" => "new-host", "port" => 5432}}, 500
    end

    test "preserves existing config when updating a top-level key" do
      # Set up initial state with the existing test data
      # We know from the setup that we have app and database keys

      # Update with a new top-level key
      Server.put("llm_client_type", "echo")

      # Verify all original keys are preserved
      assert {:ok, _app_data} = Server.get("app")
      assert {:ok, _db_data} = Server.get("database")
      assert {:ok, "echo"} = Server.get("llm_client_type")

      # The app and database sections should still have their contents
      assert {:ok, "TestApp"} = Server.get("app.name")
      assert {:ok, "localhost"} = Server.get("database.host")
    end
  end
end
