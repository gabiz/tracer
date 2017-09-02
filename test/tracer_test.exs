defmodule Tracer.Test do
  use ExUnit.Case
  doctest Tracer

  import Tracer
  import Tracer.Matcher
  alias Tracer.{Tool.Count, Tool.Duration, Tool.CallSeq, Tool.Display}

  setup do
    # kill server if alive? for a fresh test
    case Process.whereis(Tracer.Server) do
      nil -> :ok
      pid ->
        Process.exit(pid, :kill)
        :timer.sleep(10)
    end
    :ok
  end

  test "can add multiple probes" do
    {:ok, pid} = Tracer.start()
    assert Process.alive?(pid)
    test_pid = self()

    tool = Tracer.tool(Display, forward_to: test_pid)
    |> Tracer.Tool.add_probe(Tracer.probe(type: :call, process: :all,
                                  match_by: local do Map.new() -> :ok end))
    |> Tracer.Tool.add_probe(Tracer.probe(type: :gc, process: self()))
    |> Tracer.Tool.add_probe(Tracer.probe(type: :set_on_link, process: [self()]))
    |> Tracer.Tool.add_probe(Tracer.probe(type: :procs, process: [self()]))
    |> Tracer.Tool.add_probe(Tracer.probe(type: :receive, process: [self()]))
    |> Tracer.Tool.add_probe(Tracer.probe(type: :send, process: [self()]))
    |> Tracer.Tool.add_probe(Tracer.probe(type: :sched, process: [self()]))

    probes = Tracer.Tool.get_probes(tool)
    assert probes ==
            [
              %Tracer.Probe{enabled?: true, flags: [:arity, :timestamp],
              process_list: [:all], type: :call,
              clauses: [%Tracer.Clause{matches: 0, type: :call,
                        desc: "local do Map.new() -> :ok end",
                        flags: [:local],
                        match_specs: [{[], [], [:ok]}],
              mfa: {Map, :new, 0}}]},
             %Tracer.Probe{clauses: [], enabled?: true,
              flags: [:timestamp], process_list: [test_pid],
              type: :gc},
             %Tracer.Probe{clauses: [], enabled?: true,
              flags: [:timestamp],
              process_list: [test_pid], type: :set_on_link},
             %Tracer.Probe{clauses: [], enabled?: true,
              flags: [:timestamp],
              process_list: [test_pid], type: :procs},
             %Tracer.Probe{clauses: [], enabled?: true,
              flags: [:timestamp],
              process_list: [test_pid], type: :receive},
             %Tracer.Probe{clauses: [], enabled?: true,
              flags: [:timestamp],
              process_list: [test_pid], type: :send},
             %Tracer.Probe{clauses: [], enabled?: true,
              flags: [:timestamp],
              process_list: [test_pid], type: :sched}
            ]

      Tracer.start_tool(tool)

      %{tracing: true} = :sys.get_state(Tracer.Server, 100)

      assert_receive :started_tracing

      res = :erlang.trace_info(test_pid, :flags)
      assert res == {:flags, [:arity, :garbage_collection, :running,
                      :set_on_link, :procs,
                      :call, :receive, :send, :timestamp]}
      res = :erlang.trace_info({Map, :new, 0}, :all)
      assert res == {:all,
                      [traced: :local,
                       match_spec: [{[], [], [:ok]}],
                       meta: false,
                       meta_match_spec: false,
                       call_time: false,
                       call_count: false]}

  end

  test "display tool" do
    test_pid = self()

    res = start_tool(Display,
                     forward_to: test_pid,
                     process: test_pid,
                     match: local do Map.new() -> :ok end)
    assert res == :ok

    :timer.sleep(50)
    %{tracing: true} = :sys.get_state(Tracer.Server, 100)

    Map.new()

    assert_receive :started_tracing
    res = stop_tool()
    assert res == :ok

    assert_receive %Tracer.EventCall{arity: 0, fun: :new, message: nil,
        mod: Map, pid: ^test_pid, ts: _}

    assert_receive {:done_tracing, :stop_command}
    # not expeting more events
    refute_receive(_)
  end

  test "count tool" do
    test_pid = self()

    res = start_tool(Count,
                     process: test_pid,
                     forward_to: test_pid,
                     match: global do Map.new(%{a: a}); Map.new(%{b: b}) end)
    assert res == :ok

    :timer.sleep(50)

    %{tracing: true} = :sys.get_state(Tracer.Server, 100)

    Map.new(%{})
    Map.new(%{})
    Map.new(%{})
    Map.new(%{})
    Map.new(%{a: :foo})
    Map.new(%{a: :foo})
    Map.new(%{b: :bar})
    Map.new(%{b: :bar})
    Map.new(%{b: :bar})
    Map.new(%{b: :bar})
    Map.new(%{b: :bar})
    Map.new(%{b: :bar})

    assert_receive :started_tracing
    res = stop_tool()
    assert res == :ok

    assert_receive %Count.Event{counts:
      [{[a: :foo], 2},
       {[b: :bar], 6}]}

    assert_receive {:done_tracing, :stop_command}
    # not expeting more events
    refute_receive(_)
  end

  def recur_len([], acc), do: acc
  def recur_len([_h | t], acc), do: recur_len(t, acc + 1)

  test "duration tool" do
    test_pid = self()

    res = start_tool(Duration,
                     process: test_pid,
                     forward_to: test_pid,
                     match: local Tracer.Test.recur_len(list, val))
    assert res == :ok

    :timer.sleep(50)

    %{tracing: true} = :sys.get_state(Tracer.Server, 100)

    recur_len([1, 2, 3, 4, 5], 0)
    recur_len([1, 2, 3, 5], 2)

    assert_receive :started_tracing
    assert_receive(%{pid: ^test_pid, mod: Tracer.Test, fun: :recur_len,
        arity: 2, duration: _, message: [[:list, [1, 2, 3, 4, 5]], [:val, 0]]})
    assert_receive(%{pid: ^test_pid, mod: Tracer.Test, fun: :recur_len,
        arity: 2, duration: _, message: [[:list, [1, 2, 3, 5]], [:val, 2]]})

    res = stop_tool()
    assert res == :ok

    assert_receive {:done_tracing, :stop_command}
    # not expeting more events
    refute_receive(_)
  end

  test "call_seq tool" do
    test_pid = self()

    res = start_tool(CallSeq,
                     process: test_pid,
                     forward_to: test_pid,
                     show_args: true,
                     show_return: true,
                     start_match: Tracer.Test)
    assert res == :ok

    :timer.sleep(10)

    assert_receive :started_tracing

    recur_len([1, 2, 3, 4, 5], 0)

    :timer.sleep(10)
    res = stop_tool()
    assert res == :ok

    assert_receive %CallSeq.Event{arity: 2, depth: 0, fun: :recur_len, message: [[[1, 2, 3, 4, 5], 0]], mod: Tracer.Test, pid: _, return_value: nil, type: :enter}
    assert_receive %CallSeq.Event{arity: 2, depth: 1, fun: :recur_len, message: [[[2, 3, 4, 5], 1]], mod: Tracer.Test, pid: _, return_value: nil, type: :enter}
    assert_receive %CallSeq.Event{arity: 2, depth: 2, fun: :recur_len, message: [[[3, 4, 5], 2]], mod: Tracer.Test, pid: _, return_value: nil, type: :enter}
    assert_receive %CallSeq.Event{arity: 2, depth: 3, fun: :recur_len, message: [[[4, 5], 3]], mod: Tracer.Test, pid: _, return_value: nil, type: :enter}
    assert_receive %CallSeq.Event{arity: 2, depth: 4, fun: :recur_len, message: [[[5], 4]], mod: Tracer.Test, pid: _, return_value: nil, type: :enter}
    assert_receive %CallSeq.Event{arity: 2, depth: 5, fun: :recur_len, message: [[[], 5]], mod: Tracer.Test, pid: _, return_value: nil, type: :enter}
    assert_receive %CallSeq.Event{arity: 2, depth: 5, fun: :recur_len, message: nil, mod: Tracer.Test, pid: _, return_value: 5, type: :exit}
    assert_receive %CallSeq.Event{arity: 2, depth: 4, fun: :recur_len, message: nil, mod: Tracer.Test, pid: _, return_value: 5, type: :exit}
    assert_receive %CallSeq.Event{arity: 2, depth: 3, fun: :recur_len, message: nil, mod: Tracer.Test, pid: _, return_value: 5, type: :exit}
    assert_receive %CallSeq.Event{arity: 2, depth: 2, fun: :recur_len, message: nil, mod: Tracer.Test, pid: _, return_value: 5, type: :exit}
    assert_receive %CallSeq.Event{arity: 2, depth: 1, fun: :recur_len, message: nil, mod: Tracer.Test, pid: _, return_value: 5, type: :exit}
    assert_receive %CallSeq.Event{arity: 2, depth: 0, fun: :recur_len, message: nil, mod: Tracer.Test, pid: _, return_value: 5, type: :exit}

    assert_receive {:done_tracing, :stop_command}
    # not expeting more events
    refute_receive(_)
  end

end
