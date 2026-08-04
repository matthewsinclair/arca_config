defmodule Mix.Tasks.Arca.Config do
  @moduledoc "Custom mix tasks for Arca Config: mix arca.config"
  use Mix.Task

  @impl Mix.Task
  @requirements ["app.config", "app.start"]
  @shortdoc "Runs Arca Config"
  @doc "Invokes Arca Config and passes it the supplied command line params."
  def run(args) do
    Arca.Config.CLI.main(args)
  end
end
