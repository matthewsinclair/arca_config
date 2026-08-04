defmodule Arca.Config.Value do
  @moduledoc """
  Coerces configuration values that arrive as strings.

  Two callers need this and neither of them is the other: `Arca.Config.CLI`
  converts what the shell hands to `set`, and `Arca.Config.load_config_phase/0`
  converts what the shell hands to an `ARCA_CONFIG_*` override. The conversion
  lived inside the facade as a private helper of the CLI, which is why the CLI
  could not simply be lifted out with it -- the env-override path was calling it
  too, from the other side of the module.
  """

  @doc """
  Converts a string from the environment into the value it denotes.

  Booleans, integers, floats and JSON documents are recognised. Anything else --
  including a JSON document that does not parse -- is the string itself.

  ## Examples
      iex> Arca.Config.Value.from_string("true")
      true

      iex> Arca.Config.Value.from_string("42")
      42

      iex> Arca.Config.Value.from_string("3.14")
      3.14

      iex> Arca.Config.Value.from_string(~s({"host": "localhost"}))
      %{"host" => "localhost"}

      iex> Arca.Config.Value.from_string("{not json")
      "{not json"

      iex> Arca.Config.Value.from_string("localhost")
      "localhost"
  """
  @spec from_string(String.t()) :: any()
  def from_string("true"), do: true
  def from_string("false"), do: false
  def from_string("[" <> _rest = value), do: decode_or_keep(value)
  def from_string("{" <> _rest = value), do: decode_or_keep(value)
  def from_string(value), do: number_or_keep(value)

  defp decode_or_keep(value) do
    case Jason.decode(value) do
      {:ok, decoded} -> decoded
      {:error, _reason} -> value
    end
  end

  defp number_or_keep(value) do
    cond do
      Regex.match?(~r/^-?\d+$/, value) -> String.to_integer(value)
      Regex.match?(~r/^-?\d+\.\d+$/, value) -> String.to_float(value)
      true -> value
    end
  end
end
