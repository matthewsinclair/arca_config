defmodule Arca.Config.IsolationTest do
  # async: false -- reads process-global environment variables and the working
  # tree, both of which every other module in this suite mutates.
  use ExUnit.Case, async: false

  # AT-04.4 (ST0002 acceptance.md). Archetype AR-4's consequence: because the
  # config location is ambient, the suite escaped its sandbox. It created
  # `.arca_config/` inside the repo, and cleaned up `.test_app` in HOME, in the
  # working directory *and in the repo's parent directory* -- a cleanup list
  # that was itself the admission.
  #
  # `test_helper.exs` captures the baseline before ExUnit starts and installs an
  # after-suite guard that fails the run on drift. This test is the same
  # comparison made at a point where it can name what leaked.

  test "suite leaves repo tree and env exactly as found" do
    baseline = Arca.Config.Test.Isolation.baseline()

    assert Arca.Config.Test.Isolation.strays() == baseline.strays
    assert Arca.Config.Test.Isolation.working_tree() == baseline.working_tree
    assert Arca.Config.Test.Isolation.config_env() == baseline.config_env
    assert Arca.Config.Test.Isolation.app_env() == baseline.app_env
  end
end
