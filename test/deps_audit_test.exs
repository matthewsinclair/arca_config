defmodule Arca.Config.DepsAuditTest do
  # async: true -- reads mix.exs and the source tree, touches no shared state.
  use ExUnit.Case, async: true

  # AT-05.3 (AC-05.1), restated. As originally drafted this was a gate asserting
  # "declared == referenced", which would fail the build for any dependency with
  # no in-repo call site. That is the inference hv overruled: arca_config is a
  # library, and a dependency it declares can be there for its consumers. AC-05.1
  # was rewritten to default to KEEP, so a gate that deletes on silence would now
  # contradict its own acceptance criterion.
  #
  # What this does instead is make the set deliberate. Every declared dependency
  # is listed below with why it is here. Adding or removing one without saying
  # which fails this test, so the question gets answered at the moment of the
  # change rather than reconstructed later from a grep.

  # The full declared set, each with the evidence for keeping it.
  @declared %{
    jason: "used directly: JSON encode/decode on every read and write",
    optimus: "used directly: the CLI command specification (Arca.Config.CLI)",
    ok: "no in-repo call site -- kept per AC-05.1 default-KEEP, pending downstream evidence",
    castore: "no in-repo call site -- kept per AC-05.1 default-KEEP, pending downstream evidence",
    certifi: "no in-repo call site -- kept per AC-05.1 default-KEEP, pending downstream evidence",
    owl: "no in-repo call site -- arca_cli declares owl itself; kept per AC-05.1",
    ucwidth: "no in-repo call site -- kept per AC-05.1 default-KEEP, pending downstream evidence",
    pathex: "no in-repo call site -- kept per AC-05.1 default-KEEP, pending downstream evidence",
    table_rex:
      "no in-repo call site -- kept per AC-05.1 default-KEEP, pending downstream evidence",
    elixir_uuid:
      "no in-repo call site -- kept per AC-05.1 default-KEEP, pending downstream evidence",
    ex_doc: "dev only: documentation build",
    meck: "test only: one remaining use, map_test.exs forcing a put failure",
    dotenv: "dev and test only, runtime: false -- declared; config/dotenv.exs hand-parses .env"
  }

  # Read the declared set from mix.exs textually. Evaluating mix.exs inside the
  # suite would re-define the project module, so the source is the one place
  # this looks.
  defp declared_deps do
    "mix.exs"
    |> File.read!()
    |> then(&Regex.scan(~r/\{:([a-z_]+),/, &1))
    |> Enum.map(fn [_full, name] -> String.to_atom(name) end)
    |> MapSet.new()
  end

  test "every declared dependency is accounted for, and every account is declared" do
    declared = declared_deps()
    accounted = @declared |> Map.keys() |> MapSet.new()

    assert MapSet.difference(declared, accounted) |> MapSet.to_list() == [],
           "a dependency was added to mix.exs without a reason in @declared"

    assert MapSet.difference(accounted, declared) |> MapSet.to_list() == [],
           "a dependency was removed from mix.exs without removing it from @declared"
  end

  # The two that carry direct evidence, asserted rather than asserted-about.
  test "the dependencies claimed as used really are used" do
    lib = Path.wildcard("lib/**/*.ex") |> Enum.map_join("\n", &File.read!/1)

    assert lib =~ "Jason."
    assert lib =~ "Optimus."
  end
end
