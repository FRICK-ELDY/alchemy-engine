defmodule Core.FormulaStore.LocalBackend do
  @moduledoc false
  use Agent

  def start_link(opts \\ []) do
    Agent.start_link(fn -> %{} end, Keyword.put_new(opts, :name, __MODULE__))
  end

  def get(key) do
    Agent.get(__MODULE__, &Map.fetch(&1, key))
  end

  def put(key, value) do
    Agent.update(__MODULE__, &Map.put(&1, key, value))
    :ok
  end
end
