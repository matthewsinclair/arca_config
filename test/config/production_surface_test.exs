defmodule Arca.Config.ProductionSurfaceTest do
  # async: true -- reads source files and module exports, touches no shared state.
  use ExUnit.Case, async: true

  # AT-05.1 (AC-05.2) and the structural half of AC-05.6.
  #
  # These are assertions about the shape of the shipped code rather than about
  # its behaviour, and they are structural on purpose. The invariant "production
  # modules answer no test-only message" has no behavioural witness worth
  # asserting: with the clause gone, the old message reaches no `handle_info/2`
  # clause and kills the process, so a behavioural test here would have to
  # assert a crash. Reading the source states the rule directly and fails the
  # moment someone adds a backdoor back.
  #
  # What was removed: `{:reset_for_test, config}` in `Server` (zero callers -- a
  # backdoor nothing even used) and `{:reset_to_dormant, pid}` in `FileWatcher`,
  # which was a second copy of `stop_watching/0` that skipped cancelling the
  # pending timer and answered asynchronously, so the test that used it carried
  # on before the watcher had stopped.

  @production_sources Path.wildcard("lib/**/*.ex")

  test "the library ships no production modules that answer test-only messages" do
    offenders =
      Enum.filter(@production_sources, fn path ->
        source = File.read!(path)

        String.contains?(source, ":reset_for_test") or
          String.contains?(source, ":reset_to_dormant")
      end)

    assert offenders == []
  end

  test "every production source is scanned, so the check cannot pass by finding nothing" do
    assert length(@production_sources) >= 9
    assert "lib/config/server.ex" in @production_sources
    assert "lib/config/file_watcher.ex" in @production_sources
  end

  test "test control over the watcher is available through its public API" do
    assert function_exported?(Arca.Config.FileWatcher, :stop_watching, 0)
    assert function_exported?(Arca.Config.FileWatcher, :start_watching, 0)
  end

  # AC-05.6. The facade was an Application callback, an API facade and a
  # command-line program at once (AF-34). The Application callback and the start
  # phase stay -- that is what the module is -- but the CLI does not.
  test "the facade holds no CLI, conversion or watch-loop logic" do
    source = File.read!("lib/arca_config.ex")

    refute source =~ "Optimus"
    refute source =~ "watch_loop"
    refute source =~ "try_convert_value"
  end

  test "the CLI is its own module and the facade only delegates to it" do
    assert Code.ensure_loaded?(Arca.Config.CLI)
    assert Code.ensure_loaded?(Arca.Config)
    assert function_exported?(Arca.Config.CLI, :main, 1)
    assert function_exported?(Arca.Config, :main, 1)
  end

  # The conversion is shared: the CLI converts what the shell hands to `set`,
  # and the start phase converts what the shell hands to an ARCA_CONFIG_*
  # override. It belongs to neither, which is why it could not move with the CLI.
  test "string coercion has one home, used by both callers" do
    assert Code.ensure_loaded?(Arca.Config.Value)
    assert function_exported?(Arca.Config.Value, :from_string, 1)
    assert File.read!("lib/config/cli.ex") =~ "Value.from_string"
    assert File.read!("lib/arca_config.ex") =~ "Value.from_string"
  end
end
