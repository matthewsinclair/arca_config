defmodule Arca.Config.Map do
  @moduledoc """
  Provides a Map-like interface to access configuration values.

  This module implements the Access behavior, allowing for a syntax like:

      config = Arca.Config.Map.new()
      config[:database][:host]

  It also provides function-based access similar to Map:

      Arca.Config.Map.get(config, :database)
      Arca.Config.Map.get_in(config, [:database, :host])
  """

  alias Arca.Config.Error
  alias Arca.Config.Server

  defstruct []

  @type t :: %__MODULE__{}

  # Explicitly declare that we're implementing the Access behaviour
  @behaviour Access

  @doc """
  Creates a new configuration map wrapper.

  ## Returns
    - A new configuration map struct
  """
  @spec new() :: t()
  def new, do: %__MODULE__{}

  @doc """
  Gets a value from the configuration.

  ## Parameters
    - `config`: The configuration map
    - `key`: The key to get
    - `default`: A default value to return if the key is not found

  ## Returns
    - The value if found, or the default value
  """
  @spec get(t(), any(), any()) :: any()
  def get(%__MODULE__{}, key, default \\ nil) do
    case Server.get(key) do
      {:ok, value} -> value
      {:error, _reason} -> default
    end
  end

  @doc """
  Gets a value from a nested path in the configuration.

  The list form of `get/3`. `Arca.Config.Server.get/1` normalises both a
  dot-separated string and a list of keys, so these were one function written
  twice with a different parameter name.

  ## Parameters
    - `config`: The configuration map
    - `keys`: A list of keys to traverse
    - `default`: A default value to return if the path is not found

  ## Returns
    - The value if found, or the default value
  """
  @spec get_in(t(), [any()], any()) :: any()
  def get_in(%__MODULE__{} = config, keys, default \\ nil), do: get(config, keys, default)

  @doc """
  Puts a value in the configuration.

  ## Parameters
    - `config`: The configuration map
    - `key`: The key to set
    - `value`: The value to set

  ## Returns
    - A new configuration map with the updated value
  """
  @spec put(t(), any(), any()) :: t()
  def put(%__MODULE__{} = config, key, value) do
    case Server.put(key, value) do
      {:ok, _} ->
        config

      {:error, reason} ->
        raise RuntimeError, message: "Failed to put config: #{Error.message(reason)}"
    end
  end

  @doc """
  Puts a value at a nested path in the configuration.

  The list form of `put/3`, for the same reason `get_in/3` is the list form of
  `get/3` -- including the raise on a failed write.

  ## Parameters
    - `config`: The configuration map
    - `keys`: A list of keys to traverse
    - `value`: The value to set

  ## Returns
    - A new configuration map with the updated value
  """
  @spec put_in(t(), [any()], any()) :: t()
  def put_in(%__MODULE__{} = config, keys, value), do: put(config, keys, value)

  @doc """
  Checks if a key exists in the configuration.

  ## Parameters
    - `config`: The configuration map
    - `key`: The key to check

  ## Returns
    - `true` if the key exists, `false` otherwise
  """
  @spec has_key?(t(), any()) :: boolean()
  def has_key?(%__MODULE__{}, key) do
    case Server.get(key) do
      {:ok, _} -> true
      {:error, _} -> false
    end
  end

  # Implement Access behavior for bracket access syntax

  @impl Access
  def fetch(%__MODULE__{}, key) do
    case Server.get(key) do
      {:ok, value} -> {:ok, value}
      {:error, _} -> :error
    end
  end

  @impl Access
  def get_and_update(%__MODULE__{} = config, key, fun) do
    current_value = get(config, key)

    case fun.(current_value) do
      {get_value, update_value} ->
        {get_value, put(config, key, update_value)}

      :pop ->
        pop(config, key)
    end
  end

  @doc """
  Removes a key from the configuration and returns its value.

  Deletes through `Arca.Config.Server.delete/1`, the same write path every other
  mutation uses, so the removal is persisted and notified like any other change.
  This used to return the value and leave the key in place, on the stated
  grounds that keys could not be deleted -- `Server.delete/1` has always existed
  (ruling R7).

  A key that is not set pops as `nil` and deletes nothing, matching `Access`.
  """
  @impl Access
  def pop(%__MODULE__{} = config, key) do
    config
    |> get(key)
    |> pop_present(config, key)
  end

  defp pop_present(nil, config, _key), do: {nil, config}

  defp pop_present(current_value, config, key) do
    case Server.delete(key) do
      {:ok, _} ->
        {current_value, config}

      {:error, reason} ->
        raise RuntimeError, message: "Failed to delete config: #{Error.message(reason)}"
    end
  end
end
