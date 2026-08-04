defmodule Arca.Config.CLITest do
  # async: false -- the CLI reads and writes through the shared configuration
  # server and its single on-disk file.
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias Arca.Config.CLI
  alias Arca.Config.Test.Support

  # AT-05.2 (AC-05.3, ruling R3). The CLI has one dispatch path, through the
  # Optimus specification. It used to have two: a hand-written `case` on `argv`
  # caught get/set/list/watch first, so the ~60-line spec and its four handlers
  # could never run (AF-11). Every test here goes through `main/1`, so a spec
  # that stopped matching would fail them -- which is the property the two-path
  # arrangement could not have.

  setup do
    app_name = Arca.Config.Cfg.config_domain() |> to_string()
    path_var = "#{String.upcase(app_name)}_CONFIG_PATH"
    file_var = "#{String.upcase(app_name)}_CONFIG_FILE"

    original_env = %{path: System.get_env(path_var), file: System.get_env(file_var)}

    test_dir = Path.join(System.tmp_dir(), "arca_cli_test_#{:rand.uniform(10_000)}")
    File.mkdir_p!(test_dir)

    File.write!(
      Path.join(test_dir, "config.json"),
      Jason.encode!(%{"app" => %{"name" => "TestApp"}})
    )

    System.put_env(path_var, test_dir)
    System.put_env(file_var, "config.json")

    Support.ensure_started({Registry, keys: :duplicate, name: Arca.Config.Registry})
    Support.ensure_started({Registry, keys: :duplicate, name: Arca.Config.CallbackRegistry})
    Support.ensure_started({Registry, keys: :duplicate, name: Arca.Config.SimpleCallbackRegistry})
    Support.ensure_started(Arca.Config.Cache)
    Support.ensure_started(Arca.Config.Server)

    Arca.Config.Server.reload()

    on_exit(fn ->
      Support.restore_env(path_var, original_env.path)
      Support.restore_env(file_var, original_env.file)
      File.rm_rf!(test_dir)
    end)

    :ok
  end

  test "get reaches the Optimus spec and prints the value" do
    assert capture_io(fn -> CLI.main(["get", "app.name"]) end) == "TestApp\n"
  end

  test "set reaches the Optimus spec and persists the value" do
    capture_io(fn -> CLI.main(["set", "app.name", "RenamedApp"]) end)

    assert {:ok, "RenamedApp"} = Arca.Config.get("app.name")
  end

  # The dispatch this replaces joined the trailing arguments of `set` with
  # spaces, so an unquoted multi-word value worked. The spec's `value` arg takes
  # one word, so the subcommand allows unknown args and rejoins them.
  test "set keeps an unquoted multi-word value whole" do
    capture_io(fn -> CLI.main(["set", "app.motto", "there", "can", "be", "only", "one"]) end)

    assert {:ok, "there can be only one"} = Arca.Config.get("app.motto")
  end

  test "set converts what the shell hands it" do
    capture_io(fn -> CLI.main(["set", "app.port", "4000"]) end)
    capture_io(fn -> CLI.main(["set", "app.debug", "false"]) end)

    assert {:ok, 4000} = Arca.Config.get("app.port")
    assert {:ok, false} = Arca.Config.get("app.debug")
  end

  test "list prints the whole configuration as JSON" do
    output = capture_io(fn -> CLI.main(["list"]) end)

    assert {:ok, %{"app" => %{"name" => "TestApp"}}} = Jason.decode(output)
  end

  # A non-string value used to be handed to `IO.puts/1` directly, which treats a
  # list as chardata: a JSON array written by `set` and read back by `get`
  # printed control characters rather than the array.
  test "get prints a structured value as JSON rather than as chardata" do
    capture_io(fn -> CLI.main(["set", "app.ports", "[4000, 4001]"]) end)

    output = capture_io(fn -> CLI.main(["get", "app.ports"]) end)

    assert {:ok, [4000, 4001]} = Jason.decode(output)
  end

  test "an unrecognised command reports itself instead of failing silently" do
    assert capture_io(fn -> CLI.main([]) end) =~ "Invalid command"
  end

  test "the facade's main/1 delegates to the CLI" do
    assert capture_io(fn -> Arca.Config.main(["get", "app.name"]) end) == "TestApp\n"
  end
end
