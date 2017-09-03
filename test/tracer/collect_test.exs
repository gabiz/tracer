defmodule Tracer.Collect.Test do
  use ExUnit.Case
  alias Tracer.Collect

  test "add_sample() collects events" do
    collection = Collect.new()
    |> Collect.add_sample(:a, :foo)
    |> Collect.add_sample(:a, :bar)
    assert collection.collections == %{a: [:bar, :foo]}
  end

  test "get_collections() returns the collections" do
    collection = Collect.new()
    |> Collect.add_sample(:a, :foo)
    |> Collect.add_sample(:a, :bar)
    |> Collect.get_collections()

    assert collection == [{:a, [:foo, :bar]}]
  end

  test "get_collections() handles multile keys" do
    collection = Collect.new()
    |> Collect.add_sample(:a, :foo)
    |> Collect.add_sample(:a, :bar)
    |> Collect.add_sample(:b, :baz)
    |> Collect.get_collections()

    assert collection == [{:a, [:foo, :bar]}, {:b, [:baz]}]
  end

end
