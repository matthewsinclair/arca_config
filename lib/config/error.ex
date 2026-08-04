defmodule Arca.Config.Error do
  @moduledoc """
  The one error shape the library returns, and the one place that builds it.

  Every public failure is `{:error, {:config, reason, detail}}`:

  - `reason` is a machine-matchable atom. Match on it. It will not be reworded.
  - `detail` is the key path for key-scoped failures, and the underlying cause
    otherwise -- a posix atom, or a descriptive binary for a parse failure.

  Callers that care about the difference match the reason; callers that only
  need to tell a person what happened call `message/1`.

  ## Why this exists

  A missing key used to be reported four different ways: `"Key not found"` from
  the server, `"'<key>' not found"` from `Cfg`, `"No such property: <name>"`
  from `inspect_property/1`, and `:not_found` from the cache. Every consumer had
  to guess which one it was about to receive, and the only way to classify one
  was to match on English prose -- our downstream CLI genuinely does
  `String.downcase(reason) =~ "not found"`, which means rewording a message was
  a silent breaking change to its behaviour.

  Nothing is lost in the move. The descriptive text that used to *be* the error
  is now the `detail`, so a parse failure still says where it failed.

  ## What is deliberately not this shape

  - `Arca.Config.Cache` keeps `{:error, :not_found}` and
    `{:error, :cache_unavailable}`. Its "not found" means *not cached*, which is
    not the same claim as *no such key* -- the cache is an accelerator, and
    collapsing the two would make a cold cache indistinguishable from a missing
    key at the one layer that has to tell them apart.
  - `Server.remove_callback/1` keeps `{:error, :not_found}`. A callback
    reference is not a configuration key, and there is no key path to report.

  ## Examples

      iex> Arca.Config.Error.not_found(["database", "host"])
      {:error, {:config, :not_found, ["database", "host"]}}

      iex> Arca.Config.Error.message({:config, :not_found, ["database", "host"]})
      "key not found: database.host"

      iex> Arca.Config.Error.message({:config, :write_failed, :eacces})
      "failed to write configuration: eacces"
  """

  @type reason :: :not_found | :load_failed | :write_failed
  @type detail :: [String.t()] | atom() | String.t()
  @type t :: {:config, reason(), detail()}

  @doc "The key at `key_path` is not set."
  @spec not_found([String.t()]) :: {:error, t()}
  def not_found(key_path), do: {:error, {:config, :not_found, key_path}}

  @doc "The configuration could not be read or parsed. `cause` says why."
  @spec load_failed(term()) :: {:error, t()}
  def load_failed(cause), do: {:error, {:config, :load_failed, cause}}

  @doc "The configuration could not be persisted. `cause` is usually a posix atom."
  @spec write_failed(term()) :: {:error, t()}
  def write_failed(cause), do: {:error, {:config, :write_failed, cause}}

  @doc """
  Renders a reason for a person.

  Total by construction: the last clause takes anything at all, so reporting an
  error can never itself fail on the shape of the error it is reporting.
  """
  @spec message(term()) :: String.t()
  def message({:config, :not_found, key_path}) when is_list(key_path),
    do: "key not found: #{Enum.join(key_path, ".")}"

  def message({:config, :not_found, key}), do: "key not found: #{describe(key)}"

  def message({:config, :load_failed, cause}),
    do: "failed to load configuration: #{describe(cause)}"

  def message({:config, :write_failed, cause}),
    do: "failed to write configuration: #{describe(cause)}"

  def message({:config, reason, detail}), do: "#{reason}: #{describe(detail)}"
  def message(reason), do: describe(reason)

  defp describe(value) when is_binary(value), do: value
  defp describe(value) when is_atom(value), do: to_string(value)
  defp describe(value), do: inspect(value)
end
