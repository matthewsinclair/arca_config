defmodule Arca.Config.CacheTest do
  # async: false -- the cache is one named process owning one named ETS table,
  # cleared in setup and terminated outright by the unavailability test.
  use ExUnit.Case, async: false

  alias Arca.Config.Cache

  setup do
    # Ensure the cache is running and cleared for each test.
    Arca.Config.Test.Support.ensure_started(Arca.Config.Cache)
    Cache.clear()

    :ok
  end

  describe "put/2 and get/1" do
    test "stores and retrieves a value" do
      Cache.put(["app", "name"], "TestApp")
      assert {:ok, "TestApp"} = Cache.get(["app", "name"])
    end

    test "handles different value types" do
      # Integer
      Cache.put(["count"], 42)
      assert {:ok, 42} = Cache.get(["count"])

      # Float
      Cache.put(["temperature"], 98.6)
      assert {:ok, 98.6} = Cache.get(["temperature"])

      # Boolean
      Cache.put(["enabled"], true)
      assert {:ok, true} = Cache.get(["enabled"])

      # Map
      Cache.put(["settings"], %{"theme" => "dark"})
      assert {:ok, %{"theme" => "dark"}} = Cache.get(["settings"])

      # List
      Cache.put(["tags"], ["elixir", "config"])
      assert {:ok, ["elixir", "config"]} = Cache.get(["tags"])
    end

    test "returns error for non-existent key" do
      assert {:error, :not_found} = Cache.get(["missing"])
    end

    test "put returns the value in an ok tuple" do
      assert {:ok, "TestValue"} = Cache.put(["test"], "TestValue")
    end
  end

  describe "clear/0" do
    test "removes all values from cache" do
      # Add some values
      Cache.put(["a"], 1)
      Cache.put(["b"], 2)

      # Clear the cache
      assert {:ok, :cleared} = Cache.clear()

      # Values should be gone
      assert {:error, :not_found} = Cache.get(["a"])
      assert {:error, :not_found} = Cache.get(["b"])
    end
  end

  # AT-01.4 (ST0002 acceptance.md). AF-05: the rescue clauses fabricated success
  # "for tests" and could not fire for their stated purpose -- a dead GenServer
  # produces an exit, not an exception, so `rescue` never caught it.
  describe "cache unavailable (AR-1)" do
    setup do
      Supervisor.terminate_child(Arca.Config.Supervisor, Arca.Config.Cache)
      on_exit(fn -> Supervisor.restart_child(Arca.Config.Supervisor, Arca.Config.Cache) end)
      :ok
    end

    test "cache unavailability is distinct from key-miss" do
      assert {:error, :cache_unavailable} = Cache.get(["app", "name"])
      assert {:error, :cache_unavailable} = Cache.put(["app", "name"], "TestApp")
      assert {:error, :cache_unavailable} = Cache.clear()
      assert {:error, :cache_unavailable} = Cache.invalidate(["app"])
    end
  end

  describe "invalidate/1" do
    test "removes a specific key" do
      # Add some values
      Cache.put(["parent", "child1"], "value1")
      Cache.put(["parent", "child2"], "value2")
      Cache.put(["other"], "other")

      # Invalidate one key
      assert {:ok, :invalidated} = Cache.invalidate(["parent", "child1"])

      # The invalidated key should be gone, others should remain
      assert {:error, :not_found} = Cache.get(["parent", "child1"])
      assert {:ok, "value2"} = Cache.get(["parent", "child2"])
      assert {:ok, "other"} = Cache.get(["other"])
    end

    test "removes child keys when parent is invalidated" do
      # Add parent and nested values
      Cache.put(["parent"], %{"child1" => "value1", "child2" => "value2"})
      Cache.put(["parent", "child1"], "value1")
      Cache.put(["parent", "child2"], "value2")
      Cache.put(["parent", "nested", "grandchild"], "nested")

      # Invalidate parent
      assert {:ok, :invalidated} = Cache.invalidate(["parent"])

      # All nested keys should be gone
      assert {:error, :not_found} = Cache.get(["parent"])
      assert {:error, :not_found} = Cache.get(["parent", "child1"])
      assert {:error, :not_found} = Cache.get(["parent", "child2"])
      assert {:error, :not_found} = Cache.get(["parent", "nested", "grandchild"])
    end
  end
end
