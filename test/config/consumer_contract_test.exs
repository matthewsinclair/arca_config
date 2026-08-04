defmodule Arca.Config.ConsumerContractTest do
  # async: false -- drives the named Arca.Config.Server and the process-global
  # config location, the same shared state every other module in this suite uses.
  use ExUnit.Case, async: false

  alias Arca.Config.Server
  alias Arca.Config.Test.Support

  # AT-00.1 (ST0002 acceptance.md) -- covers AC-00.4, ratified by hv 2026-08-04.
  #
  # arca_config is a library, so a grep inside it cannot see a single consumer.
  # hv's ruling on the dependency retraction makes that explicit: in-repo silence
  # over public surface is evidence of UNTESTED CONTRACT SURFACE, not of deadness,
  # and the remedy is coverage rather than deletion. This module is that coverage.
  #
  # Every assertion below is a call arca_cli actually makes, cited to the line in
  # arca_cli that makes it. It is deliberately mostly-green: it is a tripwire, not
  # a feature test. WP-02 rewrites the error dialect and WP-05 removes surface,
  # and this module is what turns "we broke our consumer" from something WP-06
  # discovers during the rebuild into a local failure at the moment of the change.
  #
  # Adding a consumer call here is cheaper than discovering it downstream. When a
  # new consumer appears, its calls belong in this module.

  setup do
    app_name = Arca.Config.Cfg.config_domain() |> to_string()
    path_var = "#{String.upcase(app_name)}_CONFIG_PATH"
    file_var = "#{String.upcase(app_name)}_CONFIG_FILE"

    original_env = %{path: System.get_env(path_var), file: System.get_env(file_var)}

    test_dir = Path.join(System.tmp_dir(), "arca_consumer_test_#{:rand.uniform(10_000)}")
    File.mkdir_p!(test_dir)

    File.write!(
      Path.join(test_dir, "config.json"),
      Jason.encode!(%{"database" => %{"host" => "localhost"}})
    )

    System.put_env(path_var, test_dir)
    System.put_env(file_var, "config.json")

    Support.ensure_started({Registry, keys: :duplicate, name: Arca.Config.Registry})
    Support.ensure_started({Registry, keys: :duplicate, name: Arca.Config.CallbackRegistry})
    Support.ensure_started({Registry, keys: :duplicate, name: Arca.Config.SimpleCallbackRegistry})
    Support.ensure_started(Arca.Config.Cache)
    Support.ensure_started(Arca.Config.Server)

    Server.reload()

    on_exit(fn ->
      Support.restore_env(path_var, original_env.path)
      Support.restore_env(file_var, original_env.file)
      File.rm_rf!(test_dir)
    end)

    {:ok, %{test_dir: test_dir}}
  end

  describe "the surface arca_cli binds to" do
    # arca_cli.ex:128-130 gates every settings read and write on this exact
    # three-part probe. If any part goes false, arca_cli does not crash -- it
    # silently stops persisting settings, which is why this is pinned here.
    test "arca_cli's config-availability probe passes" do
      assert Code.ensure_loaded?(Arca.Config)
      assert function_exported?(Arca.Config, :register_change_callback, 2)
      assert Process.whereis(Arca.Config.Server) != nil
    end

    # The tripwire, stated on its own so a failure names the cause. This symbol
    # has zero callers inside arca_config and zero callers inside arca_cli -- it
    # is used only as a liveness proxy (arca_cli.ex:129). A call-graph search
    # cannot find that consumer, so deleting the function looks free and is not.
    test "register_change_callback/2 survives as arca_cli's liveness proxy" do
      assert function_exported?(Arca.Config, :register_change_callback, 2)
    end

    test "the facade exposes the functions arca_cli calls" do
      assert function_exported?(Arca.Config, :get, 1)
      assert function_exported?(Arca.Config, :put, 2)
      assert function_exported?(Arca.Config, :switch_config_location, 1)
      assert function_exported?(Arca.Config.Server, :start_link, 1)
      assert function_exported?(Arca.Config.Server, :reload, 0)
    end

    # RED until WP-02 (AC-02.3). `get_config_location/0` has never existed in any
    # commit of arca_config, yet arca_cli's testing helper documents it as the way
    # to inspect the temp config (cli_command_helper.ex:350). It is documentation
    # rather than a live call site, so nothing raises today -- but arca_cli tells
    # its users the function is there. `delete/1` and `delete!/1` exist on Server
    # and are absent from the facade, which is the same gap in the other direction.
    test "the facade exposes the location and delete API its docs promise" do
      assert function_exported?(Arca.Config, :get_config_location, 0)
      assert function_exported?(Arca.Config, :delete, 1)
      assert function_exported?(Arca.Config, :delete!, 1)
    end
  end

  describe "the shapes arca_cli pattern-matches on" do
    # arca_cli.ex:1055 pipes a stringified setting id into get/1 and matches
    # {:ok, value}; arca_cli.ex:1136 matches {:ok, _} from put/2 and halts its
    # reduce on anything else.
    test "get/1 and put/2 round-trip a dotted string key" do
      assert {:ok, "localhost"} = Arca.Config.get("database.host")
      assert {:ok, "replaced"} = Arca.Config.put("database.host", "replaced")
      assert {:ok, "replaced"} = Arca.Config.get("database.host")
    end

    # arca_cli.ex:1025 matches {:ok, config} and renders {:error, reason} into
    # "Failed to load configuration: ...". A bare :ok or a map would break it.
    test "Server.reload/0 answers {:ok, config} with the config as a map" do
      assert {:ok, config} = Server.reload()
      assert %{"database" => %{"host" => "localhost"}} = config
    end

    # cli_command_helper.ex:500 calls switch_config_location/1 with a keyword
    # list and matches {:ok, previous}; :509 passes that same `previous` value
    # straight back in to restore. The returned value must therefore be
    # accepted as an argument -- the round-trip is the contract, not the shape.
    test "switch_config_location/1 accepts a keyword list and round-trips what it returns" do
      other_dir = Path.join(System.tmp_dir(), "arca_consumer_switch_#{:rand.uniform(10_000)}")
      File.mkdir_p!(other_dir)
      on_exit(fn -> File.rm_rf!(other_dir) end)

      File.write!(
        Path.join(other_dir, "test_config.json"),
        Jason.encode!(%{"database" => %{"host" => "switched"}})
      )

      assert {:ok, previous} =
               Arca.Config.switch_config_location(path: other_dir, file: "test_config.json")

      assert {:ok, "switched"} = Arca.Config.get("database.host")

      assert {:ok, _restored} = Arca.Config.switch_config_location(previous)
      assert {:ok, "localhost"} = Arca.Config.get("database.host")
    end
  end

  describe "the error dialect arca_cli reads" do
    # arca_cli.ex:1080-1092 classifies a missing setting with three clauses: the
    # bare atom :not_found, a binary whose downcase contains "not found", and a
    # generic fallback that renders "cannot read setting X: <reason>". Today we
    # return a binary, so arca_cli takes clause two and prints the right message.
    #
    # This test is why R1 is a visible decision rather than an accident. The
    # proposed {:error, {:config, :not_found, key_path}} matches none of arca_cli
    # 0.5.0's accepting clauses, so it falls to the fallback and a missing key
    # starts rendering as "cannot read setting X: {:config, :not_found, [...]}".
    # That is a degradation, not a crash -- and when WP-02 lands it, this test
    # must be changed deliberately and recorded in impl.md's changed-tests ledger.
    test "a missing key is reported in the dialect arca_cli classifies as not-found" do
      assert {:error, reason} = Arca.Config.get("no.such.key")
      assert reason == "Key not found"
      assert String.downcase(reason) =~ "not found"
    end
  end
end
