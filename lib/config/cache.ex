defmodule Arca.Config.Cache do
  @moduledoc """
  Manages an ETS-based cache for configuration values.

  This module provides fast in-memory access to configuration values
  without needing to read from disk for every access. The cache is
  automatically synchronized with configuration changes.
  """

  use GenServer

  @table_name :arca_config_cache

  # Client API

  @doc """
  Starts the cache process.
  """
  def start_link(_opts) do
    GenServer.start_link(__MODULE__, nil, name: __MODULE__)
  end

  @doc """
  Gets a value from the cache by key path.

  ## Parameters
    - `key_path`: A list of keys representing the path to the value

  ## Returns
    - `{:ok, value}` if the value is found
    - `{:error, :not_found}` if the value is not in the cache
    - `{:error, :cache_unavailable}` if the cache process is not running
  """
  @spec get(list(String.t())) :: {:ok, any()} | {:error, :not_found | :cache_unavailable}
  def get(key_path) when is_list(key_path) do
    case :ets.lookup(@table_name, key_path) do
      [{^key_path, value}] -> {:ok, value}
      [] -> {:error, :not_found}
    end
  rescue
    # The named table only exists while the cache process owns it. A missing
    # table means the cache is down, which is not the same answer as "this key
    # is not cached" -- callers must be able to tell them apart.
    ArgumentError -> {:error, :cache_unavailable}
  end

  @doc """
  Puts a value in the cache.

  ## Parameters
    - `key_path`: A list of keys representing the path to the value
    - `value`: The value to store

  ## Returns
    - `{:ok, value}` with the value that was stored
    - `{:error, :cache_unavailable}` if the cache process is not running
  """
  @spec put(list(String.t()), any()) :: {:ok, any()} | {:error, :cache_unavailable}
  def put(key_path, value) when is_list(key_path) do
    call_cache({:put, key_path, value})
  end

  @doc """
  Clears the entire cache.

  ## Returns
    - `{:ok, :cleared}` when the cache is successfully cleared
    - `{:error, :cache_unavailable}` if the cache process is not running
  """
  @spec clear() :: {:ok, :cleared} | {:error, :cache_unavailable}
  def clear do
    call_cache(:clear)
  end

  @doc """
  Invalidates a specific key path and all its children from the cache.

  ## Parameters
    - `key_path`: A list of keys representing the path to invalidate

  ## Returns
    - `{:ok, :invalidated}` when the key path is successfully invalidated
    - `{:error, :cache_unavailable}` if the cache process is not running
  """
  @spec invalidate(list(String.t())) :: {:ok, :invalidated} | {:error, :cache_unavailable}
  def invalidate(key_path) when is_list(key_path) do
    call_cache({:invalidate, key_path})
  end

  # A down cache exits the caller rather than raising, so the previous `rescue`
  # clauses could never fire for the case they claimed to cover -- they only
  # fabricated success. Catch the exit and report it, so unavailability reaches
  # the caller as a value.
  defp call_cache(message) do
    GenServer.call(__MODULE__, message)
  catch
    :exit, _reason -> {:error, :cache_unavailable}
  end

  # Server callbacks

  @impl true
  def init(_) do
    # Create ETS table owned by this process
    :ets.new(@table_name, [:set, :protected, :named_table])
    {:ok, nil}
  end

  @impl true
  def handle_call({:put, key_path, value}, _from, state) do
    :ets.insert(@table_name, {key_path, value})
    {:reply, {:ok, value}, state}
  end

  @impl true
  def handle_call(:clear, _from, state) do
    :ets.delete_all_objects(@table_name)
    {:reply, {:ok, :cleared}, state}
  end

  @impl true
  def handle_call({:invalidate, key_path}, _from, state) do
    # Remove the exact key path
    :ets.delete(@table_name, key_path)

    # Also remove any children of this key path
    # Find all keys in the table
    all_keys =
      :ets.tab2list(@table_name)
      |> Enum.map(fn {k, _v} -> k end)
      |> Enum.filter(fn k -> prefix?(key_path, k) end)

    # Delete all keys that have this key_path as prefix
    Enum.each(all_keys, fn k -> :ets.delete(@table_name, k) end)

    {:reply, {:ok, :invalidated}, state}
  end

  # Private functions

  defp prefix?(prefix, list) do
    prefix_size = length(prefix)

    with true <- length(list) >= prefix_size,
         {potential_prefix, _rest} <- Enum.split(list, prefix_size) do
      potential_prefix == prefix
    else
      _ -> false
    end
  end
end
