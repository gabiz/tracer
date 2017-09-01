defmodule Tracer.Matcher.Test do
  use ExUnit.Case

  alias Tracer.Matcher
  import Tracer.Matcher

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

  test "body with message including one literal" do
    ms = match do -> message(:a) end
    assert ms == [{[], [], [{:message, [:a]}] }]
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

  test "body with :ok statement" do
    ms = match do (a, b, c) -> :ok end
    assert ms == [{[:"$1", :"$2", :"$3"],
                  [],
                  [:ok] }]
  end

  test "global with erlang module and any function" do
    res = global do :lists._ -> :foo end
    assert res == %Matcher{flags: [:global],
                    mfa: {:lists, :_, :_},
                    ms: [{:_, [], [:foo]}],
                    desc: "global do :lists._() -> :foo end"
                  }
  end

  test "global with erlang module and any arity" do
    res = global do :lists.sum -> :foo end
    assert res == %Matcher{flags: [:global],
                    mfa: {:lists, :sum, :_},
                    ms: [{:_, [], [:foo]}],
                    desc: "global do :lists.sum() -> :foo end"
                  }
  end

  test "global with erlang module and function" do
    res = global do :lists.max(a) -> :foo end
    assert res == %Matcher{flags: [:global],
                    mfa: {:lists, :max, 1},
                    ms: [{[:"$1"], [], [:foo]}],
                    desc: "global do :lists.max(a) -> :foo end"
                  }
  end

  test "global with Module._ mfa" do
    res = global do Map._ -> :foo end
    assert res == %Matcher{flags: [:global],
                    mfa: {Map, :_, :_},
                    ms: [{:_, [], [:foo]}],
                    desc: "global do Map._() -> :foo end"
                  }
  end

  test "global with don't care mfa" do
    res = global do _ -> :foo end
    assert res == %Matcher{flags: [:global],
                    mfa: {:_, :_, :_},
                    ms: [{:_, [], [:foo]}],
                    desc: "global do _ -> :foo end"
                  }
  end

  test "global with count including bindings" do
    res = global do Map.get(a, b) -> count(a, b) end
    assert res == %Matcher{flags: [:global],
                    mfa: {Map, :get, 2},
                    ms: [{[:"$1", :"$2"], [],
                      [message: [[:_cmd, :count], [:a, :"$1"], [:b, :"$2"]]]}],
                    desc: "global do Map.get(a, b) -> count(a, b) end"
                  }
  end

  test "local with count including bindings" do
    res = local do Map.get(a, b) -> count(a, b) end
    assert res == %Matcher{flags: [:local],
                    mfa: {Map, :get, 2},
                    ms: [{[:"$1", :"$2"], [],
                      [message: [[:_cmd, :count], [:a, :"$1"], [:b, :"$2"]]]}],
                    desc: "local do Map.get(a, b) -> count(a, b) end"
                    }
  end

  test "local without single clause" do
    res = local Map.get(a, b)
    assert res == %Matcher{flags: [:local],
                    mfa: {Map, :get, 2},
                    ms: [{[:"$1", :"$2"], [],
                      [message: [[:a, :"$1"], [:b, :"$2"]]]}],
                    desc: "local Map.get(a, b)"
                    }
  end

  test "local without single clause no params" do
    res = local Map.get(_, _)
    assert res == %Matcher{flags: [:local],
                    mfa: {Map, :get, 2},
                    ms: [{[:_, :_], [],
                      [message: []]}],
                    desc: "local Map.get(_, _)"
                    }
  end

  test "local without single clause no params no fun" do
    res = local Map._
    assert res == %Matcher{flags: [:local],
                    mfa: {Map, :_, :_},
                    ms: [{:_, [],
                      [message: []]}],
                    desc: "local Map._()"
                    }
  end

  test "local without single clause match all" do
    res = local _
    assert res == %Matcher{flags: [:local],
                    mfa: {:_, :_, :_},
                    ms: [{:_, [],
                      [message: []]}],
                    desc: "local _"
                    }
  end

  test "local without body with multiple clauses" do
    res = local do Map.get(a, b); Map.get(d, e) end
    assert res == %Matcher{flags: [:local],
                    mfa: {Map, :get, 2},
                    ms: [{[:"$1", :"$2"], [],
                      [message: [[:a, :"$1"], [:b, :"$2"]]]},
                         {[:"$1", :"$2"], [],
                      [message: [[:d, :"$1"], [:e, :"$2"]]]}],
                    desc: "local do \n  Map.get(a, b)\n  Map.get(d, e)\n end"
                    }
  end

  test "local without body with one do clause" do
    res = local do Map.get(a, b) end
    assert res == %Matcher{flags: [:local],
                    mfa: {Map, :get, 2},
                    ms: [{[:"$1", :"$2"], [],
                      [message: [[:a, :"$1"], [:b, :"$2"]]]}],
                    desc: "local do Map.get(a, b) end"
                    }
  end
end
