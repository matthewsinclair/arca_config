defmodule Arca.Config.NotificationMatrixTest do
  # async: false -- counts how many times each notification channel fires, so any
  # concurrent mutation of the shared configuration would show up as an extra.
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias Arca.Config.FileWatcher
  alias Arca.Config.Server

  # AT-03.1 (ST0002 acceptance.md). The ratified matrix: three channels
  # (per-key subscribers, 1-arity config callbacks, 0-arity callbacks) x five
  # mutation paths (put, delete, reload, external detect, switch). Every channel
  # fires exactly once per mutation event on every path; per-key subscribers
  # fire when the value at their path actually changed.
  #
  # Probe P5 recorded what this replaces: per-key fired only on internal
  # put/delete and never for the external change the watcher exists to catch,
  # 1-arity fired only on external, and 0-arity fired twice per detected change.

  setup do
    app_name = Arca.Config.Cfg.config_domain() |> to_string()
    path_var = "#{String.upcase(app_name)}_CONFIG_PATH"
    file_var = "#{String.upcase(app_name)}_CONFIG_FILE"

    original_env = %{
      path: System.get_env(path_var),
      file: System.get_env(file_var)
    }

    test_dir = Path.join(System.tmp_dir(), "arca_matrix_test_#{:rand.uniform(10_000)}")
    other_dir = Path.join(test_dir, "other")
    File.mkdir_p!(test_dir)
    File.mkdir_p!(other_dir)
    test_file = Path.join(test_dir, "config.json")

    File.write!(
      test_file,
      Jason.encode!(%{"database" => %{"host" => "localhost", "port" => 5432}})
    )

    File.write!(
      Path.join(other_dir, "config.json"),
      Jason.encode!(%{"database" => %{"host" => "elsewhere"}})
    )

    System.put_env(path_var, test_dir)
    System.put_env(file_var, "config.json")

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
    Arca.Config.Test.Support.ensure_started(FileWatcher)

    Server.reload()

    on_exit(fn ->
      Arca.Config.Test.Support.restore_env(path_var, original_env.path)
      Arca.Config.Test.Support.restore_env(file_var, original_env.file)
      File.rm_rf!(test_dir)
    end)

    {:ok, %{test_dir: test_dir, test_file: test_file, other_dir: other_dir}}
  end

  # Register all three channels against the test process and clean them up.
  # Returns once every registration is live.
  defp watch_all_channels(key) do
    test_pid = self()

    Server.subscribe(key)
    Arca.Config.register_change_callback(:matrix, fn config -> send(test_pid, {:cb1, config}) end)
    {:ok, ref} = Arca.Config.add_callback(fn -> send(test_pid, :cb0) end)

    on_exit(fn ->
      Arca.Config.unregister_change_callback(:matrix)
      Arca.Config.remove_callback(ref)
    end)

    :ok
  end

  # Every channel fired exactly once for this event, with the per-key message
  # carrying the new value.
  defp assert_each_channel_fired_once(key_path, value) do
    assert_receive {:config_updated, ^key_path, ^value}, 1000
    assert_receive {:cb1, _config}, 1000
    assert_receive :cb0, 1000

    refute_receive {:config_updated, ^key_path, _}, 100
    refute_receive {:cb1, _}, 100
    refute_receive :cb0, 100
  end

  test "matrix: each channel fires once per covered path" do
    watch_all_channels("database.host")

    assert {:ok, "put-host"} = Server.put("database.host", "put-host")
    assert_each_channel_fired_once(["database", "host"], "put-host")

    assert {:ok, :deleted} = Server.delete("database.host")
    assert_each_channel_fired_once(["database", "host"], nil)
  end

  test "matrix: reload fires every channel once", %{test_file: test_file} do
    watch_all_channels("database.host")

    File.write!(test_file, Jason.encode!(%{"database" => %{"host" => "reloaded"}}))

    assert {:ok, _config} = Server.reload()
    assert_each_channel_fired_once(["database", "host"], "reloaded")
  end

  test "matrix: an externally detected change fires every channel once", %{test_file: test_file} do
    watch_all_channels("database.host")

    FileWatcher.start_watching(test_file)
    :sys.get_state(FileWatcher)

    File.write!(test_file, Jason.encode!(%{"database" => %{"host" => "edited-by-hand"}}))
    send(FileWatcher, :check_file)

    assert_each_channel_fired_once(["database", "host"], "edited-by-hand")
  end

  test "matrix: switching location fires every channel once", %{other_dir: other_dir} do
    watch_all_channels("database.host")

    assert {:ok, _previous} =
             Arca.Config.switch_config_location(path: other_dir, file: "config.json")

    assert_each_channel_fired_once(["database", "host"], "elsewhere")
  end

  test "per-key subscribers hear a change made through an ancestor put" do
    watch_all_channels("database.host")

    # The write is at the ancestor, but the subscribed path's value changed, so
    # the subscriber must hear about it. Walking self-and-ancestors from the
    # written path -- the old behaviour -- never reaches a descendant.
    assert {:ok, _value} = Server.put("database", %{"host" => "replaced", "port" => 5432})

    assert_each_channel_fired_once(["database", "host"], "replaced")
  end

  test "a subscriber whose value did not change is not notified" do
    watch_all_channels("database.port")

    assert {:ok, "unrelated"} = Server.put("database.host", "unrelated")

    refute_receive {:config_updated, ["database", "port"], _}, 200
    # The event still happened, so the whole-config channels still fire.
    assert_receive {:cb1, _config}, 1000
    assert_receive :cb0, 1000
  end

  # Pins the contract for a consumer this repo does not have. Widening the
  # matrix means 1-arity callbacks now fire on put/delete/reload/switch, not
  # only on external change, so a callback that reads or writes config is
  # reachable in a way it was not before. In-repo silence over this surface is
  # untested contract, not absent contract: these two tests are the pinning.
  test "a callback may call back into the config without deadlocking" do
    test_pid = self()

    Arca.Config.register_change_callback(:reentrant, fn _config ->
      send(test_pid, {:read_back, Arca.Config.get("database.host")})
    end)

    on_exit(fn -> Arca.Config.unregister_change_callback(:reentrant) end)

    assert {:ok, "reentrant-host"} = Server.put("database.host", "reentrant-host")

    assert_receive {:read_back, {:ok, "reentrant-host"}}, 1000
  end

  test "a callback that writes the value it was given does not loop" do
    test_pid = self()

    # The classic derived-settings callback: it writes in response to a change.
    # Because an event only exists when the config actually changed, its own
    # idempotent write terminates instead of re-triggering itself forever.
    Arca.Config.register_change_callback(:writer, fn config ->
      host = get_in(config, ["database", "host"])
      Arca.Config.put("database.mirror", host)
      send(test_pid, :writer_ran)
    end)

    on_exit(fn -> Arca.Config.unregister_change_callback(:writer) end)

    assert {:ok, "looping-host"} = Server.put("database.host", "looping-host")

    # Two events: the put, then the callback's own write of a new mirror value.
    assert_receive :writer_ran, 1000
    assert_receive :writer_ran, 1000
    refute_receive :writer_ran, 300

    assert {:ok, "looping-host"} = Arca.Config.get("database.mirror")
  end

  test "an unchanged put is not a change event" do
    watch_all_channels("database.host")

    assert {:ok, "localhost"} = Server.put("database.host", "localhost")

    refute_receive {:config_updated, _, _}, 200
    refute_receive {:cb1, _}, 100
    refute_receive :cb0, 100
  end

  test "a failed mutation notifies nothing", %{test_file: test_file} do
    watch_all_channels("database.host")
    File.chmod!(test_file, 0o444)
    on_exit(fn -> File.chmod(test_file, 0o644) end)

    capture_log(fn ->
      assert {:error, {:config, :write_failed, :eacces}} =
               Server.put("database.host", "never-lands")
    end)

    refute_receive {:config_updated, _, _}, 200
    refute_receive {:cb1, _}, 100
    refute_receive :cb0, 100
  end
end
