defmodule SvgSpriteEx.RuntimeData.CacheTest do
  use ExUnit.Case, async: false

  alias SvgSpriteEx.RuntimeData.Cache

  setup do
    Cache.invalidate()
    on_exit(&Cache.invalidate/0)
  end

  test "does not expose a generation reset" do
    refute function_exported?(Cache, :reset, 0)
  end

  test "fetch retries when invalidation overtakes an in-flight load" do
    {:ok, backing_data} = Agent.start_link(fn -> :old end)
    test_process = self()

    loader = fn ->
      value = Agent.get(backing_data, &Function.identity/1)
      send(test_process, {:loaded, self(), value})
      maybe_block_old_load(value)
    end

    fetch_task = Task.async(fn -> Cache.fetch(loader) end)

    assert_receive {:loaded, loader_process, :old}, 5_000
    Agent.update(backing_data, fn :old -> :new end)
    Cache.invalidate()
    send(loader_process, :release)

    assert Task.await(fetch_task) == :new
    assert_receive {:loaded, ^loader_process, :new}, 5_000
    assert Cache.fetch(fn -> flunk("new data was not cached") end) == :new
  end

  test "fetch retries when invalidation occurs after the post-load generation check" do
    assert_retry_when_invalidated_at(:after_load_generation_check)
  end

  test "fetch retries when invalidation occurs after publication before return" do
    assert_retry_when_invalidated_at(:after_publish)
  end

  defp assert_retry_when_invalidated_at(phase) do
    {:ok, backing_data} = Agent.start_link(fn -> :old end)

    loader = fn -> Agent.get(backing_data, &Function.identity/1) end
    hook = barrier_hook(self(), phase)
    fetch_task = Task.async(fn -> Cache.fetch(loader, hook) end)

    assert_receive {:cache_barrier, loader_process, ^phase}, 5_000
    Agent.update(backing_data, fn :old -> :new end)
    Cache.invalidate()
    send(loader_process, {:release_cache_barrier, phase})

    assert Task.await(fetch_task) == :new
    assert Cache.fetch(fn -> flunk("new data was not cached") end) == :new
  end

  defp barrier_hook(test_process, barrier_phase) do
    fn phase ->
      maybe_block_at_barrier(phase, barrier_phase, test_process)
    end
  end

  defp maybe_block_at_barrier(phase, phase, test_process) do
    case Process.get({__MODULE__, phase}) do
      nil ->
        Process.put({__MODULE__, phase}, :released)
        send(test_process, {:cache_barrier, self(), phase})
        await_barrier_release(phase)

      :released ->
        :ok
    end
  end

  defp maybe_block_at_barrier(_phase, _barrier_phase, _test_process), do: :ok

  defp await_barrier_release(phase) do
    receive do
      {:release_cache_barrier, ^phase} -> :ok
    after
      5_000 -> flunk("timed out waiting to release #{phase} cache barrier")
    end
  end

  defp maybe_block_old_load(:old) do
    receive do
      :release -> :old
    after
      5_000 -> flunk("timed out waiting to release old load")
    end
  end

  defp maybe_block_old_load(value), do: value
end
