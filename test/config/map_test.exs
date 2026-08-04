defmodule Arca.Config.MapTest do
  # async: false -- the Map facade reads and writes through the shared
  # configuration server and its single on-disk file.
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias Arca.Config.Map, as: ConfigMap
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
    test_dir = Path.join(System.tmp_dir(), "arca_map_test_#{:rand.uniform(1000)}")
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

    {:ok, %{config: ConfigMap.new(), test_file: test_file}}
  end

  describe "get/3" do
    test "retrieves a value by key", %{config: config} do
      assert "TestApp" = ConfigMap.get(config, "app.name")
    end

    test "returns default for non-existent key", %{config: config} do
      assert "default" = ConfigMap.get(config, "missing", "default")
    end

    test "returns nil for non-existent key with no default", %{config: config} do
      assert is_nil(ConfigMap.get(config, "missing"))
    end
  end

  describe "get_in/3" do
    test "retrieves a value by key path", %{config: config} do
      assert "TestApp" = ConfigMap.get_in(config, ["app", "name"])
    end

    test "returns default for non-existent path", %{config: config} do
      assert "default" = ConfigMap.get_in(config, ["app", "missing"], "default")
    end
  end

  describe "put/3" do
    test "updates a value", %{config: config} do
      # Update a value
      new_config = ConfigMap.put(config, "app.name", "NewApp")

      # Check the value was updated
      assert "NewApp" = ConfigMap.get(new_config, "app.name")

      # Check it's also accessible through Server API
      assert {:ok, "NewApp"} = Server.get("app.name")
    end

    test "returns the same struct", %{config: config} do
      new_config = ConfigMap.put(config, "app.name", "NewApp")
      assert new_config == config
    end

    # Was a `:meck` mock of `Server.put/2` returning `{:error, "Test error"}`,
    # on the stated grounds that a real write failure was "a bit tricky to test".
    # It is two lines, and the rest of the suite already does it this way. The
    # mock also hid a real defect: it returned a *binary* reason, so it kept
    # passing when AC-02.2 changed reasons to tuples and this raise started
    # failing with Protocol.UndefinedError instead of the message it promises.
    test "raises with the rendered reason when the write fails", %{test_file: test_file} do
      File.chmod!(test_file, 0o444)
      on_exit(fn -> File.chmod(test_file, 0o644) end)

      # Captured, not printed: the production write failure logs at error level.
      log =
        capture_log(fn ->
          assert_raise RuntimeError,
                       ~r/Failed to put config: failed to write configuration: eacces/,
                       fn ->
                         ConfigMap.put(ConfigMap.new(), "app.name", "never-lands")
                       end
        end)

      assert log =~ "Failed to write config file"
    end
  end

  describe "put_in/3" do
    test "updates a value by path", %{config: config} do
      # Update a nested value
      new_config = ConfigMap.put_in(config, ["database", "host"], "new-host")

      # Check the value was updated
      assert "new-host" = ConfigMap.get_in(new_config, ["database", "host"])

      # Check it's also accessible through Server API
      assert {:ok, "new-host"} = Server.get(["database", "host"])
    end
  end

  describe "has_key?/2" do
    test "returns true for existing key", %{config: config} do
      assert ConfigMap.has_key?(config, "app.name")
    end

    test "returns false for non-existent key", %{config: config} do
      refute ConfigMap.has_key?(config, "missing")
    end
  end

  describe "Access behavior" do
    test "supports bracket access for getting values", %{config: config} do
      assert "TestApp" = config["app"]["name"]
      assert 5432 = config["database"]["port"]
    end

    test "bracket access with non-existent key returns nil", %{config: config} do
      assert is_nil(config["missing"])
    end

    test "get_and_update works with Access.get_and_update", %{config: config} do
      {old_value, new_config} =
        Access.get_and_update(config, "app.name", fn current ->
          {current, "UpdatedName"}
        end)

      assert old_value == "TestApp"
      assert "UpdatedName" = ConfigMap.get(new_config, "app.name")
    end

    # AT-02.4 (ruling R7). `Access.pop/2` returned the value and left the key in
    # place, with a comment claiming keys could not be deleted -- `Server.delete/1`
    # has always existed. The behaviour this replaces is in impl.md's ledger.
    test "pop deletes through the one write path" do
      config = ConfigMap.new()
      ConfigMap.put(config, "app.doomed", "here")

      {value, _config} = Access.pop(config, "app.doomed")

      assert value == "here"
      assert {:error, _} = Server.get("app.doomed")
    end

    test "pop on a missing key returns nil and deletes nothing" do
      config = ConfigMap.new()

      {value, _config} = Access.pop(config, "app.never_existed")

      assert value == nil
      assert {:ok, "TestApp"} = Server.get("app.name")
    end

    test "get_and_update's :pop branch deletes through the same path" do
      config = ConfigMap.new()
      ConfigMap.put(config, "app.doomed_too", "here")

      {value, _config} = Access.get_and_update(config, "app.doomed_too", fn _current -> :pop end)

      assert value == "here"
      assert {:error, _} = Server.get("app.doomed_too")
    end
  end
end
