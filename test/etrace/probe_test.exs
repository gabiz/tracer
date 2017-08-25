defmodule ETrace.Probe.Test do
  use ExUnit.Case
  alias ETrace.Probe
  alias ETrace.Clause
  import ETrace.Matcher

  test "new returns an error if does not include type argument" do
    assert Probe.new(param: :foo) == {:error, :missing_type}
  end

  test "new returns an error if receives an invalid type" do
    assert Probe.new(type: :foo) == {:error, :invalid_type}
  end

  test "new returns a new probe with the correct type" do
    %Probe{} = probe = Probe.new(type: :call)
    assert probe.type == :call
    assert probe.process_list == []
    assert probe.enabled? == true
  end

  test "process_list stores new processes" do
    probe = Probe.new(type: :call)
      |> Probe.process_list([:c.pid(0, 1, 0)])
      |> Probe.process_list([self(), self()])
    assert probe.process_list == [self()]
  end

  test "add_process adds the new processes" do
    probe = Probe.new(type: :call)
      |> Probe.add_process([self(), self(), :c.pid(0, 1, 0)])
    assert probe.process_list == [self(), :c.pid(0, 1, 0)]
  end

  test "add_process adds the new process" do
    probe = Probe.new(type: :call)
      |> Probe.add_process(self())
      |> Probe.add_process(self())
    assert probe.process_list == [self()]
  end

  test "remove_process removes process" do
    probe = Probe.new(type: :call)
      |> Probe.add_process(self())
      |> Probe.remove_process(self())
    assert probe.process_list == []
  end

  test "add_clauses return an error when not receiving clauses" do
    res = Probe.new(type: :call)
    |> Probe.add_clauses(42)

    assert res == {:error, [{:not_a_clause, 42}]}
  end

  test "add_clauses return an error if the clause type does not match probe" do
    res = Probe.new(type: :process)
      |> Probe.add_clauses(Clause.new() |> Clause.put_mfa())

    assert res == {:error,
                  [{:invalid_clause_type, Clause.new() |> Clause.put_mfa()}]}

  end

  test "add_clauses stores clauses" do
    probe = Probe.new(type: :call)
      |> Probe.add_clauses(Clause.new() |> Clause.put_mfa())

    %Probe{} = probe
    assert Probe.clauses(probe) == [Clause.new() |> Clause.put_mfa()]
  end

  test "remove_clause removes the clause" do
    probe = Probe.new(type: :call)
      |> Probe.add_clauses(Clause.new() |> Clause.put_mfa(Map))
      |> Probe.add_clauses(Clause.new() |> Clause.put_mfa())
      |> Probe.remove_clauses(Clause.new() |> Clause.put_mfa())

      assert Probe.clauses(probe) == [Clause.new() |> Clause.put_mfa(Map)]
  end

  test "enable, disable and enabled? work as expected" do
    probe = Probe.new(type: :call)
      |> Probe.disable()
    assert Probe.enabled?(probe) == false
    probe = Probe.enable(probe)
    assert Probe.enabled?(probe) == true
  end

  test "valid? returns an error if process_list is not configured" do
    probe = Probe.new(type: :call)
    assert Probe.valid?(probe) == {:error, :missing_processes}
  end

  test "arity enables or disables arity flag" do
    probe = Probe.new(type: :call)
      |> Probe.arity(false)
    refute Enum.member?(probe.flags, :arity)
    probe = Probe.arity(probe, true)
    assert Enum.member?(probe.flags, :arity)
  end

  test "probe can be created using shorthand options" do
    probe = Probe.new(
            type: :call,
            in_process: self(),
            with_fun: {Map, :get, 2},
            filter_by: match do (a, b) -> message(a, b) end)

    %Probe{} = probe
    assert probe.type == :call
    assert probe.process_list == [self()]
    assert Enum.count(probe.clauses) == 1
    clause = hd(probe.clauses)
    assert Clause.get_mfa(clause) == {Map, :get, 2}
    expected_specs = match do (a, b) -> message(a, b) end
    assert clause.match_specs == expected_specs
  end

  test "probe can be created using match_by option" do
    probe = Probe.new(
            type: :call,
            in_process: self(),
            match_by: global do Map.get(a, b) -> message(a, b) end)

    %Probe{} = probe
    assert probe.type == :call
    assert probe.process_list == [self()]
    assert probe.flags == [:arity, :timestamp]
    assert Enum.count(probe.clauses) == 1
    clause = hd(probe.clauses)
    assert Clause.get_mfa(clause) == {Map, :get, 2}
    assert Clause.get_flags(clause) == [:global]
    expected_specs = match do (a, b) -> message(a, b) end
    assert clause.match_specs == expected_specs
  end

  test "probe can be created using type shortcut" do
    probe = Probe.call(
            in_process: self(),
            match_by: global do Map.get(a, b) -> message(a, b) end)

    %Probe{} = probe
    assert probe.type == :call
    assert probe.process_list == [self()]
    assert probe.flags == [:arity, :timestamp]
    assert Enum.count(probe.clauses) == 1
    clause = hd(probe.clauses)
    assert Clause.get_mfa(clause) == {Map, :get, 2}
    assert Clause.get_flags(clause) == [:global]
    expected_specs = match do (a, b) -> message(a, b) end
    assert clause.match_specs == expected_specs
  end

  test "get_trace_cmds returns the expected command list" do
    probe = Probe.call(
            in_process: self(),
            match_by: global do Map.get(a, b) -> message(a, b) end)

    [trace_pattern_cmd, trace_cmd] = Probe.get_trace_cmds(probe)

    assert trace_pattern_cmd == [
      fun: &:erlang.trace_pattern/3,
      mfa: {Map, :get, 2},
      match_spec: [{[:"$1", :"$2"], [], [message: [[:a, :"$1"], [:b, :"$2"]]]}],
      flag_list: [:global]]

    test_pid = self()
    assert trace_cmd == [
      fun: &:erlang.trace/3,
      pid_port_spec: test_pid,
      how: true,
      flag_list: [:call, :arity, :timestamp]]
  end

  test "get_trace_cmds raises an exception if the probe is invalid" do
    probe = Probe.new(type: :call)

    assert_raise RuntimeError, "invalid probe {:error, :missing_processes}", fn ->
      Probe.get_trace_cmds(probe)
    end
  end
end
