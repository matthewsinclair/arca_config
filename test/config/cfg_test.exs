defmodule Arca.Config.Cfg.Test do
  # async: false -- mutates the config-location environment variables and, in two
  # tests, the working directory itself.
  use ExUnit.Case, async: false
  alias Arca.Config.Cfg

  # Set up temporary test environment for doctests.
  #
  # Per-test, not setup_all: several doctests in this module set a config-location
  # env var and then delete it, wiping the value this block establishes. Before
  # ruling R4 that damage was invisible, because a load from the resulting
  # nonexistent location still reported success with an empty config. Re-asserting
  # the location per test makes the module order-independent.
  #
  # It no longer writes a copy into the repository's own `.arca_config/` "to
  # handle tests that rely on the default path": nothing relies on the default
  # path now that test_helper.exs gives the whole run a disposable location.
  setup do
    # Set up test paths for doctest
    app_name = Arca.Config.Cfg.config_domain() |> to_string()
    test_path = System.tmp_dir!()
    test_file = "config_test.json"
    app_specific_path_var = "#{String.upcase(app_name)}_CONFIG_PATH"
    app_specific_file_var = "#{String.upcase(app_name)}_CONFIG_FILE"

    original_path = System.get_env(app_specific_path_var)
    original_file = System.get_env(app_specific_file_var)

    System.put_env(app_specific_path_var, test_path)
    System.put_env(app_specific_file_var, test_file)

    # Ensure test file exists
    config_file = Path.join(test_path, test_file)
    File.mkdir_p!(Path.dirname(config_file))

    File.write!(
      config_file,
      ~s({"id": "DOT_SLASH_DOT_LL_SLASH_CONFIG_DOT_JSON", "database": {"host": "localhost"}})
    )

    # Load the location this setup just established. `Cfg.get/1` used to re-read
    # the file on every call, so pointing the environment variables somewhere new
    # was enough on its own; it now delegates to the server, which holds one
    # loaded configuration. Moving the location behind the server's back and
    # expecting reads to follow is the ambient-location behaviour AR-4 removed.
    Arca.Config.Server.reload()

    on_exit(fn ->
      # Clean up test files
      File.rm(config_file)
      Arca.Config.Test.Support.restore_env(app_specific_path_var, original_path)
      Arca.Config.Test.Support.restore_env(app_specific_file_var, original_file)
    end)

    :ok
  end

  doctest Arca.Config
  doctest Arca.Config.Cfg

  # AT-04.1, AT-04.2, AT-04.3, AT-04.5 (ST0002 acceptance.md). Archetype AR-4:
  # the config location was a function of six inputs resolved fresh on every
  # access -- two env-var tiers, application config, a CWD-relative default, a
  # flip on whether the file happened to exist, and a heuristic that guessed the
  # domain by scanning started applications.
  describe "location model (AR-4)" do
    @location_vars [
      "ARCA_CONFIG_CONFIG_PATH",
      "ARCA_CONFIG_CONFIG_FILE",
      "ARCA_CONFIG_PATH",
      "ARCA_CONFIG_FILE"
    ]

    setup do
      original_env = Map.new(@location_vars, fn var -> {var, System.get_env(var)} end)
      original_domain = Application.get_env(:arca_config, :config_domain)
      original_path = Application.get_env(:arca_config, :config_path)
      original_file = Application.get_env(:arca_config, :config_file)

      Enum.each(@location_vars, &System.delete_env/1)
      Application.delete_env(:arca_config, :config_path)
      Application.delete_env(:arca_config, :config_file)

      on_exit(fn ->
        Enum.each(original_env, fn {var, value} ->
          Arca.Config.Test.Support.restore_env(var, value)
        end)

        Arca.Config.Test.Support.restore_app_env(:config_domain, original_domain)
        Arca.Config.Test.Support.restore_app_env(:config_path, original_path)
        Arca.Config.Test.Support.restore_app_env(:config_file, original_file)
      end)

      :ok
    end

    test "precedence chain end-to-end" do
      # 4. Default, lowest priority.
      assert Cfg.config_pathname() == Path.expand(".arca_config")
      assert Cfg.config_filename() == "config.json"

      # 3. Application configuration beats the default.
      Application.put_env(:arca_config, :config_path, "/from/app/env")
      Application.put_env(:arca_config, :config_file, "app_env.json")
      assert Cfg.config_pathname() == "/from/app/env"
      assert Cfg.config_filename() == "app_env.json"

      # 2. Generic environment variables beat application configuration.
      System.put_env("ARCA_CONFIG_PATH", "/from/generic")
      System.put_env("ARCA_CONFIG_FILE", "generic.json")
      assert Cfg.config_pathname() == "/from/generic"
      assert Cfg.config_filename() == "generic.json"

      # 1. App-specific environment variables win outright. The README said the
      # opposite for both of these tiers, which is what left arca_cli's env
      # isolation silently inert across nine files (AF-23).
      System.put_env("ARCA_CONFIG_CONFIG_PATH", "/from/app/specific")
      System.put_env("ARCA_CONFIG_CONFIG_FILE", "specific.json")
      assert Cfg.config_pathname() == "/from/app/specific"
      assert Cfg.config_filename() == "specific.json"

      # The resolved file is exactly those two combined, with nothing else
      # consulted.
      assert Cfg.config_file() == "/from/app/specific/specific.json"
    end

    test "config_domain deterministic without heuristic" do
      Application.delete_env(:arca_config, :config_domain)

      assert Cfg.config_domain() == :arca_config
      assert Cfg.env_var_prefix() == "ARCA_CONFIG"
    end

    test "location stable across file creation" do
      configured_dir = Path.join(System.tmp_dir!(), "arca_stability_#{:rand.uniform(10_000)}")
      File.mkdir_p!(configured_dir)
      on_exit(fn -> File.rm_rf!(configured_dir) end)

      System.put_env("ARCA_CONFIG_CONFIG_PATH", configured_dir)
      System.put_env("ARCA_CONFIG_CONFIG_FILE", "stable.json")
      expected = Path.join(configured_dir, "stable.json")

      # The configured file does not exist yet. The answer must still be the
      # configured location: resolving to somewhere else is how a put landed in
      # the repo root under a name nobody configured (AF-25, probe P3).
      refute File.exists?(expected)
      assert Cfg.config_file() == expected

      File.write!(expected, "{}")
      assert Cfg.config_file() == expected
    end

    test "shell-exported config var beats the checked-in dev default" do
      scratch = Path.join(System.tmp_dir!(), "arca_dotenv_#{:rand.uniform(10_000)}")
      File.mkdir_p!(Path.join(scratch, "config"))

      File.write!(
        Path.join([scratch, "config", ".env"]),
        "ARCA_CONFIG_CONFIG_PATH=from_the_dot_env_file\n"
      )

      dotenv_script = Path.join(File.cwd!(), "config/dotenv.exs")
      original_cwd = File.cwd!()
      System.put_env("ARCA_CONFIG_CONFIG_PATH", "from_the_shell")

      on_exit(fn ->
        File.cd!(original_cwd)
        File.rm_rf!(scratch)
      end)

      # The real script, run against a .env of our own: it reads config/.env
      # relative to the working directory.
      File.cd!(scratch)
      Code.eval_file(dotenv_script)
      File.cd!(original_cwd)

      assert System.get_env("ARCA_CONFIG_CONFIG_PATH") == "from_the_shell"
    end
  end

  describe "Arca.Config.Cfg" do
    setup do
      app_name = Arca.Config.Cfg.config_domain() |> to_string()
      app_specific_path_var = "#{String.upcase(app_name)}_CONFIG_PATH"
      app_specific_file_var = "#{String.upcase(app_name)}_CONFIG_FILE"

      # Restore exactly what was there, rather than the old
      # `System.put_env(System.get_env())`: putting back a superset cannot
      # delete a variable the test added, so isolation only appeared to work
      # because the next file overwrote what this one left behind.
      original_path = System.get_env(app_specific_path_var)
      original_file = System.get_env(app_specific_file_var)

      # A directory of this module's own, not `.#{app_name}` inside the repo.
      config_dir = Path.join(System.tmp_dir!(), "arca_cfg_test_#{:rand.uniform(10_000)}")
      config_file = Path.join(config_dir, "config.json")
      File.mkdir_p!(config_dir)

      System.put_env(app_specific_path_var, config_dir)
      System.put_env(app_specific_file_var, "config.json")

      File.write!(
        config_file,
        ~s({"id": "DOT_SLASH_DOT_LL_SLASH_CONFIG_DOT_JSON", "database": {"host": "localhost"}})
      )

      # Put things back how we found them
      on_exit(fn ->
        Arca.Config.Test.Support.restore_env(app_specific_path_var, original_path)
        Arca.Config.Test.Support.restore_env(app_specific_file_var, original_file)
        File.rm_rf!(config_dir)
      end)

      {:ok, %{config_dir: config_dir}}
    end

    # The setup above knows the concrete directory, so this asserts it. It used
    # to assert three `!= nil`s and then that `config_file/0` ended with
    # `config_pathname/0` joined to `config_filename/0` -- a restatement of
    # `config_file/0`'s implementation, which passes for any self-consistent
    # resolution including one pointing at entirely the wrong directory. That is
    # the AF-25 bug class this module exists to catch.
    test "config file path and name resolve to the configured location", %{
      config_dir: config_dir
    } do
      assert Cfg.config_pathname() == config_dir
      assert Cfg.config_filename() == "config.json"
      assert Cfg.config_file() == Path.join(config_dir, "config.json")
    end

    # Previously asserted string identity against a trailing slash, which is why
    # env-derived paths were deliberately left unexpanded while every other tier
    # was expanded (AF-28). It also left `/tmp/` and `bozo.json` in the
    # environment for whatever ran next.
    test "config file path and name via env var" do
      app_specific_path_var = "#{Cfg.env_var_prefix()}_CONFIG_PATH"
      app_specific_file_var = "#{Cfg.env_var_prefix()}_CONFIG_FILE"
      original_path = System.get_env(app_specific_path_var)
      original_file = System.get_env(app_specific_file_var)

      on_exit(fn ->
        Arca.Config.Test.Support.restore_env(app_specific_path_var, original_path)
        Arca.Config.Test.Support.restore_env(app_specific_file_var, original_file)
      end)

      System.put_env(app_specific_path_var, "/tmp/")
      System.put_env(app_specific_file_var, "bozo.json")

      # Expanded, like every other tier: the trailing slash is not preserved.
      assert Cfg.config_pathname() == "/tmp"
      assert Cfg.config_filename() == "bozo.json"
      assert Cfg.config_file() == "/tmp/bozo.json"
    end

    test "load valid configuration file (and succeed)" do
      # Check that we can load the default configuration file
      assert {:ok, config} = Cfg.load()
      assert config["id"] == "DOT_SLASH_DOT_LL_SLASH_CONFIG_DOT_JSON"
    end

    # Ruling R4 (ST0002): a missing config file is an empty config only for the
    # first-run bootstrap caller. This test previously asserted the opposite --
    # that any load of a nonexistent file succeeds with %{} -- which is how a
    # typo'd location read as a successful load of nothing (AF-06).
    test "load nonexistent configuration file (fails, and bootstraps empty)" do
      # Jam some nonexistent path into the env vars
      app_specific_path_var = "#{Cfg.env_var_prefix()}_CONFIG_PATH"
      app_specific_file_var = "#{Cfg.env_var_prefix()}_CONFIG_FILE"
      System.put_env(app_specific_path_var, "/nonexistent/path/")
      System.put_env(app_specific_file_var, "nonexistent.json")

      assert {:error, {:config, :load_failed, :enoent}} = Cfg.load()
      assert {:ok, %{}} == Cfg.load(nil, bootstrap: true)

      # Clean up
      System.delete_env(app_specific_path_var)
      System.delete_env(app_specific_file_var)
    end

    test "load malformed configuration file (and fail)" do
      # Create a temporary file with invalid JSON
      test_dir = Path.join(System.tmp_dir!(), "arca_cfg_test_malformed")
      File.mkdir_p!(test_dir)
      test_file = Path.join(test_dir, "malformed.json")
      File.write!(test_file, "{not_valid_json")

      # Set environment variables to point to our test file
      app_specific_path_var = "#{Cfg.env_var_prefix()}_CONFIG_PATH"
      app_specific_file_var = "#{Cfg.env_var_prefix()}_CONFIG_FILE"
      System.put_env(app_specific_path_var, test_dir)
      System.put_env(app_specific_file_var, "malformed.json")

      # Check that we properly fail on malformed JSON
      assert {:error, {:config, :load_failed, detail}} = Cfg.load()
      assert detail =~ "Error parsing config"

      # Clean up
      System.delete_env(app_specific_path_var)
      System.delete_env(app_specific_file_var)
      File.rm_rf!(test_dir)
    end

    test "inspect config property" do
      {:ok, id_from_string} = Cfg.inspect_property("id")
      assert id_from_string == "DOT_SLASH_DOT_LL_SLASH_CONFIG_DOT_JSON"
    end

    test "get config property" do
      {:ok, id_from_string} = Cfg.get("id")
      {:ok, id_from_atom} = Cfg.get(:id)
      assert id_from_string == "DOT_SLASH_DOT_LL_SLASH_CONFIG_DOT_JSON"
      assert id_from_atom == "DOT_SLASH_DOT_LL_SLASH_CONFIG_DOT_JSON"
    end

    test "get! config property" do
      id_from_string = Cfg.get!("id")
      id_from_atom = Cfg.get!(:id)
      assert id_from_string == "DOT_SLASH_DOT_LL_SLASH_CONFIG_DOT_JSON"
      assert id_from_atom == "DOT_SLASH_DOT_LL_SLASH_CONFIG_DOT_JSON"
    end

    # Both tests below used to open by setting ARCA_CONFIG_PATH and
    # ARCA_CONFIG_FILE -- the GENERIC tier -- while this describe's setup had
    # already set the domain-specific pair, which outranks it. Their location
    # setup therefore did nothing at all, and `/tmp/timestamp.json` was written,
    # never read, and deleted. That is AF-23's exact shape, reappearing inside
    # the suite that fixed it, and it meant two tests that looked like location
    # tests could not catch a location regression. They also cleaned up in the
    # test body rather than `on_exit`, so a failed assertion leaked both
    # variables into every test that ran after them.
    #
    # They write and read through the configured location, which is what they
    # were always trying to say.
    test "put and get a config property" do
      timestamp_in = DateTime.to_string(DateTime.utc_now())

      assert {:ok, ^timestamp_in} = Cfg.put(:timestamp, timestamp_in)
      assert {:ok, ^timestamp_in} = Cfg.get(:timestamp)
    end

    test "put! and get! a config property" do
      timestamp_in = DateTime.to_string(DateTime.utc_now())

      assert Cfg.put!(:timestamp, timestamp_in) == timestamp_in
      assert Cfg.get!(:timestamp) == timestamp_in
    end

    # The value really landed in the configured file, not merely in memory.
    test "a put through Cfg lands in the configured location", %{config_dir: config_dir} do
      Cfg.put!(:timestamp, "pinned")

      on_disk = Path.join(config_dir, "config.json") |> File.read!() |> Jason.decode!()

      assert on_disk["timestamp"] == "pinned"
    end

    test "config_data_pathname" do
      data_path = Cfg.config_data_pathname()
      expected_path = Path.join([Cfg.config_pathname(), "data", "links"])
      assert data_path == expected_path
    end
  end
end
