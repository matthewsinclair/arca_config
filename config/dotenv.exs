# Load environment variables from config/.env early in the configuration
# process, for this repository's own development and test runs.
#
# This is not a library feature: it is imported by this project's config.exs
# and is never evaluated in a project that depends on arca_config.
#
# Values here are defaults, not overrides. A variable already present in the
# environment -- exported by a developer's shell, or set by CI -- wins. It used
# to be the other way round: every line was applied unconditionally during
# config evaluation, so a variable you exported before running `mix test` was
# silently replaced before a single test ran, and a fresh clone with no .env
# file resolved a different config location than a working tree with one.

env_file = Path.join([File.cwd!(), "config", ".env"])

set_unless_present = fn key, value ->
  case System.get_env(key) do
    nil -> System.put_env(key, value)
    _already_set -> :ok
  end
end

if File.exists?(env_file) do
  env_file
  |> File.read!()
  |> String.split("\n")
  |> Enum.map(&String.trim/1)
  |> Enum.reject(&(&1 == "" or String.starts_with?(&1, "#")))
  |> Enum.each(fn line ->
    case String.split(line, "=", parts: 2) do
      [key, value] -> set_unless_present.(String.trim(key), String.trim(value, "\""))
      _malformed -> :ok
    end
  end)
end
