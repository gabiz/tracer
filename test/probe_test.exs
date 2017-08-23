defmodule ETrace.Probe.Test do
  use ExUnit.Case
  alias ETrace.Probe
  alias ETrace.Probe.Clause

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

end
