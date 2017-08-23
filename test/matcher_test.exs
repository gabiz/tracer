defmodule ETrace.Matcher.Test do
  use ExUnit.Case

  import ETrace.Matcher

  test "no params" do
    assert (match do  -> :x end) ==
           [{ [], [], [:x] }]
  end

  test "basic" do
    assert (match do x -> x end) ==
           [{ [:"$1"], [], [:"$1"] }]
  end

  test "gproc" do
    assert (match do {{:n, :l, {:client, id}}, pid, _} -> {id, pid} end) ==
           [{[{{:n, :l, {:client, :"$1"}}, :"$2", :_}], [], [{:"$1", :"$2"}]}]
  end

  test "match supports bound variables" do
    id = 5
    assert (match do {{:n, :l, {:client, ^id}}, pid, _} -> pid end) ==
           [{[{{:n, :l, {:client, 5}}, :"$1", :_}], [], [:"$1"]}]
  end

  test "gproc with 3 vars" do
    assert (match do {{:n, :l, {:client, id}}, pid, third} -> {id, pid, third} end) ==
           [{[{{:n, :l, {:client, :"$1"}}, :"$2", :"$3"}], [], [{:"$1", :"$2", :"$3"}]}]
  end

  test "gproc with 1 var and 2 bound vars" do
    one = 11
    two = 22
    assert (match do {{:n, :l, {:client, ^one}}, pid, ^two} -> {^one, pid} end) ==
           [{[{{:n, :l, {:client, 11}}, :"$1", 22}], [], [{11, :"$1"}]}]
  end

  test "cond" do
    assert (match do x when true -> 0 end) ==
           [{[:"$1"], [true], [0] }]

    assert (match do x when true and false -> 0 end) ==
           [{[:"$1"], [{ :andalso, true, false }], [0] }]
  end

  test "multiple matchs" do
    ms = match do
      x -> 0
      y -> y
    end
    assert ms == [{[:"$1"], [], [0] }, {[:"$1"], [], [:"$1"] }]
  end

  test "multiple exprs in body" do
    ms = match do x ->
      x
      0
    end
    assert ms == [{[:"$1"], [], [:"$1", 0] }]
  end

  test "body with message including literals" do
    ms = match do -> message(:a, :b, :c) end
    assert ms == [{[], [], [{:message, [:a, :b, :c]}] }]
  end

  test "body with message including bindings" do
    ms = match do (a, b, c) -> message(a, b, c) end
    assert ms == [{[:"$1", :"$2", :"$3"],
                  [],
                  [{:message, [[:a, :"$1"], [:b, :"$2"], [:c, :"$3"]]}] }]
  end

  test "body with count including bindings" do
    ms = match do (a, b, c) -> count(a, b, c) end
    assert ms == [{[:"$1", :"$2", :"$3"],
                  [],
                  [{:message,
                  [[:_cmd, :count], [:a, :"$1"], [:b, :"$2"], [:c, :"$3"]]}] }]
  end

end
