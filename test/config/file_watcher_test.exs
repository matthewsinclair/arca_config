defmodule Arca.Config.FileWatcherTest do
  # async: false -- drives the single named watcher process directly and points
  # the global config location at its own file.
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias Arca.Config.FileWatcher

  # Test the file watcher functionality without timing dependencies

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
    test_dir = Path.join(System.tmp_dir(), "arca_file_watcher_test_#{:rand.uniform(1000)}")
    File.mkdir_p!(test_dir)
    test_file = Path.join(test_dir, "test_config.json")

    # Set environment variables for test
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
          }
        },
        pretty: true
      )
    )

    # Ensure the registries, servers, and file watcher are running
    # (tolerating instances the application already owns).
    Arca.Config.Test.Support.ensure_started(
      {Registry, keys: :duplicate, name: Arca.Config.Registry}
    )

    Arca.Config.Test.Support.ensure_started(
      {Registry, keys: :duplicate, name: Arca.Config.CallbackRegistry}
    )

    Arca.Config.Test.Support.ensure_started(Arca.Config.Cache)
    Arca.Config.Test.Support.ensure_started(Arca.Config.Server)
    Arca.Config.Test.Support.ensure_started(FileWatcher)

    on_exit(fn ->
      # Restore original environment variables (delete when originally unset).
      # Restore, not delete: deleting these left every later resolution with one
      # fewer tier to consult than the run started with.
      Arca.Config.Test.Support.restore_env("ARCA_CONFIG_PATH", original_env.config_path)
      Arca.Config.Test.Support.restore_env("ARCA_CONFIG_FILE", original_env.config_file)
      Arca.Config.Test.Support.restore_env(app_specific_path_var, original_env.app_specific_path)
      Arca.Config.Test.Support.restore_env(app_specific_file_var, original_env.app_specific_file)

      # Clean up test directory
      File.rm_rf!(test_dir)
    end)

    # Return the test file path for use in tests
    {:ok, %{test_file: test_file}}
  end

  # AT-03.2 (ST0002 acceptance.md). AF-18: the watcher hard-matched
  # `{:ok, _} = Server.reload()`, so one malformed hand-edit raised a MatchError
  # and it restarted into `watching: false` with no timer -- permanent, silent
  # dormancy. Nothing tested it, because reload was meck'd.
  test "watcher survives malformed JSON and recovers", %{test_file: test_file} do
    test_pid = self()
    {:ok, ref} = Arca.Config.add_callback(fn -> send(test_pid, :config_changed) end)
    on_exit(fn -> Arca.Config.remove_callback(ref) end)

    FileWatcher.start_watching(test_file)
    watcher = Process.whereis(FileWatcher)
    :sys.get_state(FileWatcher)

    log =
      capture_log(fn ->
        File.write!(test_file, "{this is not json")
        send(FileWatcher, :check_file)
        # A synchronous call flushes the check that precedes it in the mailbox.
        assert :sys.get_state(FileWatcher).watching == true
      end)

    assert log =~ "Error parsing config"
    assert Process.whereis(FileWatcher) == watcher
    refute_receive :config_changed, 200

    # Recovery: the next valid write is detected.
    File.write!(test_file, Jason.encode!(%{"app" => %{"name" => "Recovered"}}))
    send(FileWatcher, :check_file)

    assert_receive :config_changed, 1000
    assert {:ok, "Recovered"} = Arca.Config.get("app.name")
  end

  # AT-03.3 (ST0002 acceptance.md). AF-19: the write token suppressed *any*
  # change while set and advanced `last_info` past it, so an external edit
  # landing in the 5s post-write window was dropped and never seen again. The
  # token's value was never compared, only its nil-ness.
  test "external edit within post-write window is detected", %{test_file: test_file} do
    test_pid = self()
    {:ok, ref} = Arca.Config.add_callback(fn -> send(test_pid, :config_changed) end)
    on_exit(fn -> Arca.Config.remove_callback(ref) end)

    FileWatcher.start_watching(test_file)
    :sys.get_state(FileWatcher)

    # Our own write opens the suppression window...
    assert {:ok, "OurWrite"} = Arca.Config.put("app.name", "OurWrite")
    assert_receive :config_changed, 1000

    # ...and someone edits the file by hand inside it.
    File.write!(test_file, Jason.encode!(%{"app" => %{"name" => "TheirEdit", "extra" => "x"}}))
    send(FileWatcher, :check_file)

    assert_receive :config_changed, 1000
    assert {:ok, "TheirEdit"} = Arca.Config.get("app.name")
  end

  # Replaces a test that asserted AF-19: it registered a write token, then wrote
  # *different* content by hand and asserted no notification -- enshrining the
  # suppress-everything window that lost real external edits. The contract it
  # was reaching for is this one: our own write does not come back a second time
  # as an external change.
  test "our own write is not re-notified as an external change", %{test_file: test_file} do
    test_pid = self()

    Arca.Config.register_change_callback(:test_callback, fn _config ->
      send(test_pid, :config_changed_externally)
    end)

    on_exit(fn -> Arca.Config.unregister_change_callback(:test_callback) end)

    FileWatcher.start_watching(test_file)
    :sys.get_state(FileWatcher)

    # The write itself is a change event, and is reported once.
    assert {:ok, "UpdatedApp"} = Arca.Config.put("app.name", "UpdatedApp")
    assert_receive :config_changed_externally, 1000

    # The token is still recorded for diagnostics.
    assert :sys.get_state(FileWatcher).write_token != nil

    # The watcher then sees the file we just wrote. Nothing changed relative to
    # what is already in memory, so it raises nothing.
    send(FileWatcher, :check_file)

    refute_receive :config_changed_externally, 500
  end

  # Replaces a test that meck'd Server.reload/0 and notify_external_change/0 and
  # asserted both were called. That pair was the 0-arity double-fire (AF-17):
  # reload notifies, and notify_external_change notified again. The watcher now
  # reloads, and the reload is what raises the event -- once. Tested against the
  # real server rather than a mock of it.
  test "detects file changes and notifies the server to reload", %{test_file: test_file} do
    test_pid = self()
    {:ok, ref} = Arca.Config.add_callback(fn -> send(test_pid, :config_changed) end)
    on_exit(fn -> Arca.Config.remove_callback(ref) end)

    FileWatcher.start_watching(test_file)
    :sys.get_state(FileWatcher)

    File.write!(test_file, Jason.encode!(%{"app" => %{"name" => "ExternalUpdate"}}, pretty: true))
    send(FileWatcher, :check_file)

    assert_receive :config_changed, 1000
    refute_receive :config_changed, 200

    assert {:ok, "ExternalUpdate"} = Arca.Config.get("app.name")
  end

  # From the critic pass (finding C3). `get_file_info/1` folded every File.stat
  # failure into `nil`, and `file_changed?(nil, _)` is false -- so a config file
  # that had been deleted or become unreadable was indistinguishable from one
  # that had not changed, forever, silently.
  test "a config file that disappears is reported once, and the watcher keeps watching", %{
    test_file: test_file
  } do
    FileWatcher.start_watching(test_file)
    :sys.get_state(FileWatcher)

    File.rm!(test_file)

    # `:sys.get_state/1` inside the capture is the synchronisation: it returns
    # only once the watcher has processed the :check_file already in its mailbox.
    log =
      capture_log(fn ->
        send(FileWatcher, :check_file)
        :sys.get_state(FileWatcher)
      end)

    assert log =~ "can no longer be read"

    # Reported on the transition only: a second tick with the file still gone
    # must not repeat itself, or a deleted file writes a log line per second.
    quiet =
      capture_log(fn ->
        send(FileWatcher, :check_file)
        :sys.get_state(FileWatcher)
      end)

    refute quiet =~ "can no longer be read"

    assert %{watching: true} = :sys.get_state(FileWatcher)
  end

  # The path is re-resolved every tick, so a test restoring its environment
  # variables moves it. That is a location change, not a disappearance, and it
  # used to log a warning about a file nobody had said was there -- which is how
  # this leaked into the suite's output from the suite's OWN config location.
  test "a resolved path that moves is not reported as a lost file", %{test_file: test_file} do
    FileWatcher.start_watching(test_file)
    :sys.get_state(FileWatcher)

    elsewhere = Path.join(System.tmp_dir(), "arca_watcher_moved_#{:rand.uniform(10_000)}")
    File.mkdir_p!(elsewhere)
    on_exit(fn -> File.rm_rf!(elsewhere) end)

    app_name = Arca.Config.Cfg.config_domain() |> to_string()
    path_var = "#{String.upcase(app_name)}_CONFIG_PATH"
    previous = System.get_env(path_var)
    System.put_env(path_var, elsewhere)
    on_exit(fn -> Arca.Config.Test.Support.restore_env(path_var, previous) end)

    log =
      capture_log(fn ->
        send(FileWatcher, :check_file)
        :sys.get_state(FileWatcher)
      end)

    refute log =~ "can no longer be read"
  end

  test "the watcher recovers when the file comes back", %{test_file: test_file} do
    test_pid = self()
    {:ok, ref} = Arca.Config.add_callback(fn -> send(test_pid, :config_changed) end)
    on_exit(fn -> Arca.Config.remove_callback(ref) end)

    FileWatcher.start_watching(test_file)
    :sys.get_state(FileWatcher)

    File.rm!(test_file)

    capture_log(fn ->
      send(FileWatcher, :check_file)
      :sys.get_state(FileWatcher)
    end)

    File.write!(test_file, Jason.encode!(%{"app" => %{"name" => "Restored"}}, pretty: true))
    send(FileWatcher, :check_file)

    assert_receive :config_changed, 1000
    assert {:ok, "Restored"} = Arca.Config.get("app.name")
  end

  # From the critic pass (finding C4). `start_watching/1` was a cast typed
  # `:: :ok`, so a cast to a dead watcher answered `:ok` too -- and because the
  # watcher restarts dormant and only this call re-arms it, a single crash left
  # external change detection off for the life of the VM with every caller
  # having been told it was on.
  test "start_watching/1 answers synchronously", %{test_file: test_file} do
    assert {:ok, :watching} = FileWatcher.start_watching(test_file)
    assert %{watching: true} = :sys.get_state(FileWatcher)
  end

  # Restarted through the supervisor rather than killed: `restart_child/2`
  # returns the new pid, so this is synchronous with no polling loop. What is
  # under test is `init/1` re-arming itself, and a supervised restart runs the
  # same `init/1` the supervisor would run after a crash -- OTP's own restart
  # is not this library's to prove.
  test "a watcher that restarts comes back armed rather than dormant", %{test_file: test_file} do
    FileWatcher.start_watching(test_file)
    :sys.get_state(FileWatcher)

    :ok = Supervisor.terminate_child(Arca.Config.Supervisor, FileWatcher)
    {:ok, restarted} = Supervisor.restart_child(Arca.Config.Supervisor, FileWatcher)

    assert %{watching: true} = :sys.get_state(restarted)
  end
end
