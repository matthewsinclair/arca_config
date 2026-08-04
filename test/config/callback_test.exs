defmodule Arca.Config.CallbackTest do
  # async: false -- registers callbacks in the shared registries and asserts how
  # many times each fires, which a concurrent module's writes would perturb.
  use ExUnit.Case, async: false
  doctest Arca.Config

  alias Arca.Config
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

    # Ensure the registries and servers the callbacks need are running
    # (tolerating instances the application already owns).
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

  describe "add_callback/1" do
    test "registers a 0-arity callback function" do
      # Use a unique reference to track callback execution
      test_pid = self()
      callback_fn = fn -> send(test_pid, :callback_executed) end

      # Register the callback
      assert {:ok, ref} = Config.add_callback(callback_fn)
      assert is_reference(ref)

      # Verify callback was registered correctly
      entries = Registry.lookup(Arca.Config.SimpleCallbackRegistry, :simple_callback)
      assert Enum.any?(entries, fn {_pid, {callback_ref, _fn}} -> callback_ref == ref end)
    end

    test "returns error for non-zero-arity functions" do
      # apply/3 keeps the deliberately-wrong arity out of the compiler's static
      # arity check (the is_function(_, 0) guard makes the inferred param type
      # (-> term())); we are exercising the runtime FunctionClauseError here.
      assert_raise FunctionClauseError, fn ->
        apply(Config, :add_callback, [fn _arg -> :ok end])
      end
    end
  end

  describe "remove_callback/1" do
    test "removes a registered callback" do
      test_pid = self()
      callback_fn = fn -> send(test_pid, :callback_executed) end

      # Register and then remove the callback
      {:ok, ref} = Config.add_callback(callback_fn)
      assert {:ok, :removed} = Config.remove_callback(ref)

      # Verify it was removed
      entries = Registry.lookup(Arca.Config.SimpleCallbackRegistry, :simple_callback)
      refute Enum.any?(entries, fn {_pid, {callback_ref, _fn}} -> callback_ref == ref end)
    end

    test "returns error for non-existent callback" do
      non_existent_ref = make_ref()
      assert {:error, :not_found} = Config.remove_callback(non_existent_ref)
    end
  end

  describe "notify_callbacks/0" do
    test "calls all registered callbacks" do
      # Set up test process to receive messages
      test_pid = self()

      # Register multiple callbacks
      callback1 = fn -> send(test_pid, :callback1_executed) end
      callback2 = fn -> send(test_pid, :callback2_executed) end

      {:ok, _ref1} = Config.add_callback(callback1)
      {:ok, _ref2} = Config.add_callback(callback2)

      # Manually trigger notification
      assert {:ok, :notified} = Config.notify_callbacks()

      # Verify all callbacks were executed
      assert_receive :callback1_executed, 500
      assert_receive :callback2_executed, 500
    end

    test "continues execution when a callback raises an error" do
      # Capture log output to suppress error messages during test
      ExUnit.CaptureLog.capture_log(fn ->
        # Set up test process to receive messages
        test_pid = self()

        # Register a failing callback and a successful one
        bad_callback = fn -> raise "Intentional test error" end
        good_callback = fn -> send(test_pid, :good_callback_executed) end

        {:ok, _bad_ref} = Config.add_callback(bad_callback)
        {:ok, _good_ref} = Config.add_callback(good_callback)

        # Notification should complete despite the error
        assert {:ok, :notified} = Config.notify_callbacks()

        # Good callback should still execute
        assert_receive :good_callback_executed, 500
      end)
    end
  end

  describe "automatic callback notification" do
    test "callbacks are notified on put operations" do
      test_pid = self()
      callback_fn = fn -> send(test_pid, :config_changed) end

      {:ok, _ref} = Config.add_callback(callback_fn)

      # Update configuration
      Config.put("test_key", "test_value")

      # Verify callback was triggered
      assert_receive :config_changed, 500
    end

    test "callbacks are notified on delete operations" do
      test_pid = self()
      callback_fn = fn -> send(test_pid, :config_changed) end

      # Add a value to be deleted
      Config.put("temp_key", "temp_value")

      {:ok, _ref} = Config.add_callback(callback_fn)

      # Delete the value
      Server.delete("temp_key")

      # Verify callback was triggered
      assert_receive :config_changed, 500
    end

    test "callbacks are notified on reload operations" do
      test_pid = self()
      callback_fn = fn -> send(test_pid, :config_changed) end

      {:ok, _ref} = Config.add_callback(callback_fn)

      # Reload configuration
      Config.reload()

      # Verify callback was triggered
      assert_receive :config_changed, 500
    end

    test "callbacks are notified on external file changes", %{test_file: _test_file} do
      test_pid = self()
      callback_fn = fn -> send(test_pid, :config_changed) end

      {:ok, ref} = Config.add_callback(callback_fn)

      Arca.Config.Server.notify_external_change()
      assert_receive :config_changed, 500

      # The second phase gets its own message rather than draining the first
      # phase's. Draining used to be `receive … after 0`, which stopped being
      # sound when callbacks moved off the server process: the first message may
      # still be in flight when the drain looks, so the drain finds nothing and
      # the assertion below can be satisfied by the stale message instead of by
      # the reload it claims to test. Distinct payloads cannot be confused.
      Config.remove_callback(ref)

      {:ok, reload_ref} = Config.add_callback(fn -> send(test_pid, :reloaded) end)
      on_exit(fn -> Config.remove_callback(reload_ref) end)

      Server.reload()

      assert_receive :reloaded, 500
    end
  end
end
