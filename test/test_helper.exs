# The suite is not allowed to change the working tree, the configuration
# environment variables, or anything outside its sandbox (AC-04.5).
#
# This file used to delete `.test_app` from the home directory, the working
# directory *and the repo's parent*, both before and after the run. That
# cleanup list was an admission that the suite escaped, and removing the
# evidence afterwards is what kept the escape invisible. The baseline below
# turns the same facts into a failed run instead.

# Point the suite at a disposable location of its own, before taking the
# baseline so that this location *is* the baseline.
#
# Both `config/.env` and the CI workflow set `ARCA_CONFIG_CONFIG_PATH` to
# `.arca_config`, which is inside the repository, so any test that did not
# override it wrote into the working tree.
suite_config_dir =
  Path.join(System.tmp_dir!(), "arca_config_suite_#{System.unique_integer([:positive])}")

File.mkdir_p!(suite_config_dir)

developer_env = %{
  "ARCA_CONFIG_CONFIG_PATH" => System.get_env("ARCA_CONFIG_CONFIG_PATH"),
  "ARCA_CONFIG_CONFIG_FILE" => System.get_env("ARCA_CONFIG_CONFIG_FILE")
}

System.put_env("ARCA_CONFIG_CONFIG_PATH", suite_config_dir)
System.put_env("ARCA_CONFIG_CONFIG_FILE", "config.json")

Arca.Config.Test.Isolation.capture()

ExUnit.after_suite(fn _results ->
  drift = Arca.Config.Test.Isolation.drift()

  # Hand the developer's own environment back before reporting, so a failure
  # here never leaves the shell holding the suite's temporary location.
  Enum.each(developer_env, fn {var, value} ->
    Arca.Config.Test.Support.restore_env(var, value)
  end)

  File.rm_rf!(suite_config_dir)

  case drift do
    [] ->
      :ok

    facets ->
      IO.puts("\n\nThe test suite did not leave things as it found them:\n")

      Enum.each(facets, fn {facet, was, now} ->
        IO.puts("  #{facet}\n    before: #{inspect(was)}\n    after:  #{inspect(now)}\n")
      end)

      exit({:shutdown, 1})
  end
end)

# `capture_log: true` makes hv's standing rule structural rather than a habit:
# suite output is dots only. Production logging that a test provokes is held per
# test and printed only when that test FAILS, which is the one moment it helps.
#
# Chasing individual leaks did not hold. Two rounds of "capture that one" both
# ended with another line appearing from somewhere else, because any test that
# provokes a real failure in production code emits one and nothing enforced it.
# Tests that assert ON a log still wrap it in `ExUnit.CaptureLog.capture_log/1`;
# the two compose.
ExUnit.start(capture_log: true)
