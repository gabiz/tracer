defmodule Tracer.Collect do
  @moduledoc """
  Collects samples in a map
  """
  alias __MODULE__

  defstruct collections: %{}

  def new do
    %Collect{}
  end

  def add_sample(state, key, value) do
    collection = [value | Map.get(state.collections, key, [])]
    put_in(state.collections, Map.put(state.collections, key, collection))
  end

  def get_collections(state) do
    Enum.map(state.collections, fn {key, value} ->
      {key, Enum.reverse(value)}
    end)
  end
end
