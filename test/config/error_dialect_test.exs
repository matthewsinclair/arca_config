defmodule Arca.Config.ErrorDialectTest do
  # async: false -- reads and writes through the shared configuration server and
  # its single on-disk file.
  use ExUnit.Case, async: false

  alias Arca.Config.Cfg
  alias Arca.Config.Server
  alias Arca.Config.Test.Support

  # AT-02.2 (AC-02.2, ruling R1). One canonical error shape from every entry
  # point: `{:error, {:config, reason, detail}}`.
  #
  # What this replaces: four ways of saying the same thing. `"Key not found"`
  # from the server, `"'<key>' not found"` from `Cfg`, `"No such property: <x>"`
  # from `inspect_property/1`, and `:not_found` from the cache. Classifying one
  # meant matching on English prose -- arca_cli genuinely does
  # `String.downcase(reason) =~ "not found"` (`arca_cli.ex:1080-1092`), so
  # rewording a message was a silent breaking change to its behaviour.

  setup do
    app_name = Cfg.config_domain() |> to_string()
    path_var = "#{String.upcase(app_name)}_CONFIG_PATH"
    file_var = "#{String.upcase(app_name)}_CONFIG_FILE"

    original_env = %{path: System.get_env(path_var), file: System.get_env(file_var)}

    test_dir = Path.join(System.tmp_dir(), "arca_dialect_test_#{:rand.uniform(10_000)}")
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

  describe "a missing key, from every entry point" do
    test "the facade reports the canonical shape" do
      assert {:error, {:config, :not_found, ["no", "such", "key"]}} =
               Arca.Config.get("no.such.key")
    end

    test "the server reports the canonical shape" do
      assert {:error, {:config, :not_found, ["no", "such", "key"]}} = Server.get("no.such.key")
    end

    test "Cfg reports the canonical shape" do
      assert {:error, {:config, :not_found, ["no", "such", "key"]}} = Cfg.get("no.such.key")
    end

    test "inspect_property reports the canonical shape" do
      assert {:error, {:config, :not_found, ["no_such_property"]}} =
               Cfg.inspect_property("no_such_property")
    end

    # The key path is in the error, so a caller can say which key was missing
    # without having parsed it back out of a sentence.
    test "the error carries the key path that was actually asked for" do
      assert {:error, {:config, :not_found, ["database", "port"]}} =
               Arca.Config.get("database.port")

      assert {:error, {:config, :not_found, ["database", "host", "deeper"]}} =
               Arca.Config.get("database.host.deeper")
    end
  end

  describe "the other failures carry their cause instead of a sentence" do
    test "a load failure reports the posix reason" do
      other = Path.join(System.tmp_dir(), "arca_dialect_absent_#{:rand.uniform(10_000)}")
      on_exit(fn -> File.rm_rf!(other) end)

      assert {:error, {:config, :load_failed, :enoent}} =
               Cfg.load(Path.join(other, "config.json"))
    end

    test "a parse failure keeps the detail that says where it failed", %{test_dir: test_dir} do
      broken = Path.join(test_dir, "broken.json")
      File.write!(broken, "{not valid json")

      assert {:error, {:config, :load_failed, detail}} = Cfg.load(broken)
      assert detail =~ "Error parsing config"
    end
  end

  describe "rendering for people" do
    test "a missing key renders with its dotted path" do
      assert {:error, reason} = Arca.Config.get("database.port")
      assert Arca.Config.Error.message(reason) == "key not found: database.port"
    end

    test "the bang functions raise the rendered message" do
      assert_raise RuntimeError, ~r/key not found: database\.port/, fn ->
        Arca.Config.get!("database.port")
      end
    end

    # Total by construction: reporting an error must never fail on the shape of
    # the error it is reporting.
    test "an unrecognised reason still renders" do
      assert Arca.Config.Error.message(:some_atom) == "some_atom"
      assert Arca.Config.Error.message("already a sentence") == "already a sentence"
      assert Arca.Config.Error.message({:totally, :unexpected}) == "{:totally, :unexpected}"
    end
  end

  describe "what deliberately keeps its own shape" do
    # The cache's "not found" means NOT CACHED, which is not the same claim as
    # NO SUCH KEY. The one layer that has to tell a cold cache from a missing
    # key is the layer that reads the cache first.
    test "the cache still distinguishes not-cached from cache-unavailable" do
      assert {:error, :not_found} = Arca.Config.Cache.get(["never", "cached", "here"])
    end

    test "a callback reference that was never registered is not a config key" do
      assert {:error, :not_found} = Server.remove_callback(make_ref())
    end
  end
end
