defmodule Arca.Config.Test.Isolation do
  @moduledoc """
  Captures and compares the state a test run is not allowed to change: the
  working tree, the environment variables that steer configuration, and the
  handful of paths this suite has historically escaped into.

  The baseline is taken in `test_helper.exs` before ExUnit starts, and compared
  both by `Arca.Config.IsolationTest` and by an after-suite guard, so a leak
  fails the run rather than being cleaned up quietly afterwards.
  """

  @baseline_key {__MODULE__, :baseline}

  @doc """
  Record the current state as the baseline for this run.
  """
  @spec capture() :: :ok
  def capture do
    :persistent_term.put(@baseline_key, %{
      strays: strays(),
      working_tree: working_tree(),
      config_env: config_env(),
      app_env: app_env()
    })
  end

  @doc """
  The baseline captured at the start of the run.
  """
  @spec baseline() :: map()
  def baseline, do: :persistent_term.get(@baseline_key)

  @doc """
  Which of the known escape paths currently exist.
  """
  @spec strays() :: [String.t()]
  def strays, do: Enum.filter(stray_paths(), &File.exists?/1)

  @doc """
  Paths outside the suite's sandbox that it has escaped into before. The old
  test_helper removed `.test_app` from HOME, the working directory and the
  repo's parent on the way in and out; that cleanup list was the admission.
  Removing the escape is the fix, and noticing it is this module's job.
  """
  @spec stray_paths() :: [String.t()]
  def stray_paths do
    home = System.user_home!()
    cwd = File.cwd!()
    parent = Path.dirname(cwd)

    for dir <- [home, cwd, parent], name <- [".test_app", ".arca_config"] do
      Path.join(dir, name)
    end
    |> Enum.reject(&(&1 == Path.join(cwd, ".arca_config")))
  end

  @doc """
  Git's view of the working tree, so a file written, changed or removed by the
  suite shows up as drift rather than as a surprise in someone's next commit.
  """
  @spec working_tree() :: String.t()
  def working_tree do
    case System.cmd("git", ["status", "--porcelain"], stderr_to_stdout: true) do
      {output, 0} -> output
      {output, _status} -> "git status unavailable: #{output}"
    end
  end

  @doc """
  The environment variables that steer configuration resolution. Restoring
  these exactly is the difference between isolation and the appearance of it:
  the old restore put back a superset and could not delete a variable a test
  had added.
  """
  @spec config_env() :: map()
  def config_env do
    System.get_env()
    |> Enum.filter(fn {key, _value} -> String.contains?(key, "CONFIG") end)
    |> Map.new()
  end

  @doc """
  The application settings that steer resolution. A module that set the config
  domain and did not put it back sent every later resolution to a different
  default directory, which is how `.test_app/` kept appearing in the repository.
  """
  @spec app_env() :: keyword()
  def app_env do
    for key <- [:config_domain, :config_path, :config_file, :default_config_path],
        do: {key, Application.get_env(:arca_config, key)}
  end

  @doc """
  Compare the current state against the baseline. Returns the differing facets.
  """
  @spec drift() :: [{atom(), any(), any()}]
  def drift do
    current = %{
      strays: strays(),
      working_tree: working_tree(),
      config_env: config_env(),
      app_env: app_env()
    }

    for {facet, was} <- baseline(),
        current[facet] != was,
        do: {facet, was, current[facet]}
  end
end
