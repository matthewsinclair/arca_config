defmodule Arca.Config.EntryPointsTest do
  # async: false -- drives the shared configuration server and the process-global
  # config location.
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias Arca.Config.Error
  alias Arca.Config.InitHelper
  alias Arca.Config.Test.Support
  alias Arca.Config.Value

  # Written after the CI coverage gate surfaced what it surfaced. `mix
  # arca.config` measured **0%**: ruling R3 chose extract over delete precisely
  # because the mix task is the documented CLI path -- the one `bin/ac cli`
  # invokes and the one the README now tells people to use -- and nothing
  # exercised it. `Arca.Config.InitHelper` was the next thinnest at 58%, and it
  # is the module a consumer calls to create its configuration in the first
  # place.
  #
  # The coverage number is not the point; these are entry points a consumer
  # reaches for on day one, and neither had a test.

  setup do
    app_name = Arca.Config.Cfg.config_domain() |> to_string()
    path_var = "#{String.upcase(app_name)}_CONFIG_PATH"
    file_var = "#{String.upcase(app_name)}_CONFIG_FILE"

    original_env = %{path: System.get_env(path_var), file: System.get_env(file_var)}

    test_dir = Path.join(System.tmp_dir(), "arca_entry_test_#{:rand.uniform(10_000)}")
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

    {:ok, %{test_dir: test_dir}}
  end

  describe "mix arca.config -- the documented CLI path (ruling R3)" do
    test "run/1 dispatches to the CLI" do
      assert capture_io(fn -> Mix.Tasks.Arca.Config.run(["get", "app.name"]) end) == "TestApp\n"
    end

    test "run/1 carries arguments through, so set persists" do
      capture_io(fn -> Mix.Tasks.Arca.Config.run(["set", "app.name", "ViaMixTask"]) end)

      assert {:ok, "ViaMixTask"} = Arca.Config.get("app.name")
    end
  end

  describe "InitHelper" do
    setup %{test_dir: test_dir} do
      original_domain = Application.get_env(:arca_config, :config_domain)
      original_cwd = File.cwd!()

      on_exit(fn ->
        File.cd!(original_cwd)
        Support.restore_app_env(:config_domain, original_domain)
        Support.restore_env("ENTRY_TEST_APP_CONFIG_PATH", nil)
        Support.restore_env("ENTRY_TEST_APP_CONFIG_FILE", nil)
      end)

      {:ok, %{work_dir: test_dir}}
    end

    test "init_config/2 creates the configuration file and returns its path", %{
      work_dir: work_dir
    } do
      target = Path.join(work_dir, "init_target")
      File.mkdir_p!(target)
      System.put_env("ENTRY_TEST_APP_CONFIG_PATH", target)
      System.put_env("ENTRY_TEST_APP_CONFIG_FILE", "config.json")

      assert {:ok, config_file} = InitHelper.init_config(:entry_test_app, %{"seeded" => true})

      assert config_file == Path.join(target, "config.json")
      assert File.exists?(config_file)
      assert %{"seeded" => true} = config_file |> File.read!() |> Jason.decode!()
    end

    test "init_config/2 sets the config domain, which is what makes it resolve", %{
      work_dir: work_dir
    } do
      target = Path.join(work_dir, "init_domain")
      File.mkdir_p!(target)
      System.put_env("ENTRY_TEST_APP_CONFIG_PATH", target)
      System.put_env("ENTRY_TEST_APP_CONFIG_FILE", "config.json")

      {:ok, _config_file} = InitHelper.init_config(:entry_test_app)

      assert Application.get_env(:arca_config, :config_domain) == :entry_test_app
    end

    # Creates `.<app>/` relative to the working directory and mutates global
    # state for the whole VM, which its own moduledoc says plainly. Run inside a
    # temporary directory so it cannot touch the repository.
    test "setup_default_config/2 creates a working-directory location", %{work_dir: work_dir} do
      File.cd!(work_dir)
      resolved_work_dir = File.cwd!()

      assert {:ok, config_file} = InitHelper.setup_default_config(:entry_test_app, %{"a" => 1})

      assert config_file == Path.join([resolved_work_dir, ".entry_test_app", "config.json"])
      assert File.exists?(config_file)
      assert %{"a" => 1} = config_file |> File.read!() |> Jason.decode!()

      assert System.get_env("ENTRY_TEST_APP_CONFIG_PATH") ==
               Path.join(resolved_work_dir, ".entry_test_app")

      assert Application.get_env(:arca_config, :config_domain) == :entry_test_app
    end
  end

  describe "Error.message/1 across every reason it can be handed" do
    test "renders each canonical reason" do
      assert Error.message({:config, :not_found, ["a", "b"]}) == "key not found: a.b"

      assert Error.message({:config, :load_failed, :enoent}) ==
               "failed to load configuration: enoent"

      assert Error.message({:config, :write_failed, :eacces}) ==
               "failed to write configuration: eacces"
    end

    # The clause that keeps this total: a reason shape nobody anticipated must
    # still render, because the alternative is failing while reporting a failure.
    test "renders a reason it has never seen" do
      assert Error.message({:config, :some_future_reason, :detail}) ==
               "some_future_reason: detail"

      assert Error.message({:config, :not_found, :an_atom_key}) == "key not found: an_atom_key"
      assert Error.message(%{unexpected: true}) == "%{unexpected: true}"
    end
  end

  describe "Value.from_string/1 across the shapes a shell can hand it" do
    test "recognises what it claims to recognise" do
      assert Value.from_string("true") == true
      assert Value.from_string("false") == false
      assert Value.from_string("42") == 42
      assert Value.from_string("-42") == -42
      assert Value.from_string("3.14") == 3.14
      assert Value.from_string("-3.14") == -3.14
      assert Value.from_string(~s({"a": 1})) == %{"a" => 1}
      assert Value.from_string("[1, 2]") == [1, 2]
    end

    test "keeps anything else as the string it came in as" do
      assert Value.from_string("localhost") == "localhost"
      assert Value.from_string("{not json") == "{not json"
      assert Value.from_string("[not json") == "[not json"
      assert Value.from_string("1.2.3") == "1.2.3"
      assert Value.from_string("") == ""
    end
  end
end
