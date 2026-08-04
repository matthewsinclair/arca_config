defmodule ArcaConfig.MixProject do
  use Mix.Project

  def project do
    [
      app: :arca_config,
      version: "0.3.0",
      elixir: "~> 1.18",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      test_coverage: [
        # Stated rather than inherited. 90 is also Elixir's default, and that is
        # the whole story of how this went unnoticed: the old CI ran
        # `mix test --cover || true`, so the threshold was never enforced and
        # nobody ever chose a number.
        threshold: 90,
        # Test support is compiled into the app by `elixirc_paths(:test)` but is
        # not shipped, so measuring it says nothing about the library. It was
        # dragging the total down by roughly four points on its own.
        ignore_modules: [
          Arca.Config.Test.Support,
          Arca.Config.Test.Isolation
        ]
      ],
      mix_tasks: [
        arca_cli: Mix.Tasks.Arca.Config,
        comment: "🛠️ Arca Config"
      ]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  def application do
    [
      mod: {Arca.Config, []},
      ansi_enabled: true
    ]
  end

  defp deps do
    [
      {:ok, "~> 2.3"},
      {:optimus, github: "matthewsinclair/arca-optimus", branch: "main", override: true},
      {:castore, "~> 1.0"},
      {:jason, "~> 1.4"},
      {:certifi, "~> 2.9"},
      {:ex_doc, "~> 0.29", only: :dev, runtime: false},
      {:owl, "~> 0.12"},
      {:ucwidth, "~> 0.2"},
      {:pathex, "~> 2.6"},
      {:table_rex, "~> 4.1"},
      {:elixir_uuid, "~> 1.2"},
      {:dotenv, "~> 3.0", only: [:dev, :test], runtime: false}
    ]
  end
end
