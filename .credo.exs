# Credo configuration for arca_config.
#
# The gate is `mix credo --strict`, which is the whole fleet's row and is left
# at the catalogue default in bin/.devbin/config.yaml -- devbin runs the check,
# and what the check MEANS is configured here, where credo configuration
# belongs. A laxer command line in devbin's config would put a project style
# ruling in the launcher's file instead of the linter's.
#
# One check is disabled, deliberately and project-wide.
%{
  configs: [
    %{
      name: "default",
      files: %{
        included: ["lib/", "test/", "mix.exs"]
      },
      strict: true,
      checks: %{
        disabled: [
          # Credo.Check.Design.AliasUsage flags `Foo.Bar.baz()` wherever an
          # `alias Foo.Bar` would shorten it. On first run it accounted for 129
          # of this project's 139 strict findings -- 116 of them in test files,
          # where the fully-qualified call is the point: a test that says
          # `Arca.Config.Server.flatten_and_cache(...)` names what it is
          # testing, and aliasing it at the top of the module hides that.
          #
          # It is disabled project-wide rather than only under test/, because a
          # style ruling that applies in one directory and not another is two
          # rulings. The remaining ten findings were real and were fixed rather
          # than configured away.
          {Credo.Check.Design.AliasUsage, []}
        ]
      }
    }
  ]
}
