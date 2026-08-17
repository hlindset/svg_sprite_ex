defmodule SvgSpriteEx.RuntimeData.Cache do
  @moduledoc false

  @cache_key {SvgSpriteEx.RuntimeData, :runtime_data}
  @generation_key {SvgSpriteEx.RuntimeData, :runtime_data_generation}
  @initial_generation {__MODULE__, :initial_generation}

  @doc false
  @spec fetch((-> term())) :: term()
  def fetch(loader) when is_function(loader, 0) do
    fetch(loader, fn _phase -> :ok end)
  end

  @doc false
  @spec fetch((-> term()), (atom() -> term())) :: term()
  def fetch(loader, hook) when is_function(loader, 0) and is_function(hook, 1) do
    generation = generation()

    case :persistent_term.get(@cache_key, :missing) do
      %{generation: ^generation, data: data} ->
        return_if_current(data, loader, hook, generation)

      _missing_or_stale ->
        load(loader, hook, generation)
    end
  end

  @doc false
  @spec invalidate() :: :ok
  def invalidate do
    :persistent_term.put(@generation_key, make_ref())
    :persistent_term.erase(@cache_key)
    :ok
  end

  @doc false
  @spec seed(term()) :: :ok
  def seed(data) do
    seed(data, generation())
  end

  defp load(loader, hook, generation) do
    data = loader.()

    case generation() do
      ^generation ->
        hook.(:after_load_generation_check)
        publish(data, loader, hook, generation)

      _new_generation ->
        fetch(loader, hook)
    end
  end

  defp publish(data, loader, hook, generation) do
    :persistent_term.put(@cache_key, %{generation: generation, data: data})
    hook.(:after_publish)
    return_if_current(data, loader, hook, generation)
  end

  defp seed(data, generation) do
    :persistent_term.put(@cache_key, %{generation: generation, data: data})

    case generation() do
      ^generation -> :ok
      _new_generation -> seed(data)
    end
  end

  defp return_if_current(data, loader, hook, generation) do
    case generation() do
      ^generation -> data
      _new_generation -> fetch(loader, hook)
    end
  end

  defp generation do
    :persistent_term.get(@generation_key, @initial_generation)
  end
end
