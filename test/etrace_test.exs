defmodule ETrace.Test do
  use ExUnit.Case
  doctest ETrace

  import ETrace
  import ETrace.Matcher

  setup do
    # kill server if alive? for a fresh test
    case Process.whereis(ETrace.Server) do
      nil -> :ok
      pid ->
        Process.exit(pid, :kill)
        :timer.sleep(10)
    end
    :ok
  end

  test "can add multiple probes" do
    {:ok, pid} = ETrace.start()
    assert Process.alive?(pid)
    test_pid = self()

    ETrace.add_probe(ETrace.probe(type: :call, process: :all,
                                  match_by: local do Map.new() -> :ok end))
    ETrace.add_probe(ETrace.probe(type: :gc, process: self()))
    ETrace.add_probe(ETrace.probe(type: :set_on_link, process: [self()]))
    ETrace.add_probe(ETrace.probe(type: :procs, process: [self()]))
    ETrace.add_probe(ETrace.probe(type: :receive, process: [self()]))
    ETrace.add_probe(ETrace.probe(type: :send, process: [self()]))
    ETrace.add_probe(ETrace.probe(type: :sched, process: [self()]))

    probes = ETrace.get_probes()
    assert probes ==
            [
              %ETrace.Probe{enabled?: true, flags: [:arity, :timestamp],
              process_list: [:all], type: :call,
              clauses: [%ETrace.Clause{matches: 0, type: :call,
                        desc: "local do Map.new() -> :ok end",
                        flags: [:local],
                        match_specs: [{[], [], [:ok]}],
              mfa: {Map, :new, 0}}]},
             %ETrace.Probe{clauses: [], enabled?: true,
              flags: [:timestamp], process_list: [test_pid],
              type: :gc},
             %ETrace.Probe{clauses: [], enabled?: true,
              flags: [:timestamp],
              process_list: [test_pid], type: :set_on_link},
             %ETrace.Probe{clauses: [], enabled?: true,
              flags: [:timestamp],
              process_list: [test_pid], type: :procs},
             %ETrace.Probe{clauses: [], enabled?: true,
              flags: [:timestamp],
              process_list: [test_pid], type: :receive},
             %ETrace.Probe{clauses: [], enabled?: true,
              flags: [:timestamp],
              process_list: [test_pid], type: :send},
             %ETrace.Probe{clauses: [], enabled?: true,
              flags: [:timestamp],
              process_list: [test_pid], type: :sched}
            ]

      ETrace.start_trace(display: [], forward_to: self())

      %{tracing: true} = :sys.get_state(ETrace.Server, 100)

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

    res = start_tool(:display,
                     forward_to: test_pid,
                     process: test_pid,
                     match: local do Map.new() -> :ok end)
    assert res == :ok

    :timer.sleep(50)
    %{tracing: true} = :sys.get_state(ETrace.Server, 100)

    Map.new()

    assert_receive :started_tracing
    res = stop_trace()
    assert res == :ok

    assert_receive %ETrace.EventCall{arity: 0, fun: :new, message: nil,
        mod: Map, pid: ^test_pid, ts: _}

    assert_receive {:done_tracing, :stop_command}
    # not expeting more events
    refute_receive(_)
  end

  test "count tool" do
    test_pid = self()

    res = start_tool(:count,
                     process: test_pid,
                     forward_to: test_pid,
                     match: global do Map.new(%{a: a}); Map.new(%{b: b}) end)
    assert res == :ok

    :timer.sleep(50)

    %{tracing: true} = :sys.get_state(ETrace.Server, 100)

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
    res = stop_trace()
    assert res == :ok

    assert_receive %ETrace.CountTool.Event{counts:
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

    res = start_tool(:duration,
                     process: test_pid,
                     forward_to: test_pid,
                     match: local ETrace.Test.recur_len(list, val))
    assert res == :ok

    :timer.sleep(50)

    %{tracing: true} = :sys.get_state(ETrace.Server, 100)

    recur_len([1, 2, 3, 4, 5], 0)
    recur_len([1, 2, 3, 5], 2)

    assert_receive :started_tracing
    assert_receive(%{pid: ^test_pid, mod: ETrace.Test, fun: :recur_len,
        arity: 2, duration: _, message: [[:list, [1, 2, 3, 4, 5]], [:val, 0]]})
    assert_receive(%{pid: ^test_pid, mod: ETrace.Test, fun: :recur_len,
        arity: 2, duration: _, message: [[:list, [1, 2, 3, 5]], [:val, 2]]})

    res = stop_trace()
    assert res == :ok

    assert_receive {:done_tracing, :stop_command}
    # not expeting more events
    refute_receive(_)
  end

  test "call_seq tool" do
    test_pid = self()

    res = start_tool(:call_seq,
                     process: test_pid,
                     forward_to: test_pid,
                     match: local ETrace.Test.recur_len(list, val))
    assert res == :ok

    # :timer.sleep(50)

    assert_receive :started_tracing

    recur_len([1, 2, 3, 4, 5], 0)

    :timer.sleep(10)
    res = stop_trace()
    assert res == :ok

    assert_receive %ETrace.CallSeqTool.Event{arity: 2, depth: 0, fun: :recur_len, message: [[:list, [1, 2, 3, 4, 5]], [:val, 0]], mod: ETrace.Test, pid: _, return_value: nil, type: :enter}
    assert_receive %ETrace.CallSeqTool.Event{arity: 2, depth: 1, fun: :recur_len, message: [[:list, [2, 3, 4, 5]], [:val, 1]], mod: ETrace.Test, pid: _, return_value: nil, type: :enter}
    assert_receive %ETrace.CallSeqTool.Event{arity: 2, depth: 2, fun: :recur_len, message: [[:list, [3, 4, 5]], [:val, 2]], mod: ETrace.Test, pid: _, return_value: nil, type: :enter}
    assert_receive %ETrace.CallSeqTool.Event{arity: 2, depth: 3, fun: :recur_len, message: [[:list, [4, 5]], [:val, 3]], mod: ETrace.Test, pid: _, return_value: nil, type: :enter}
    assert_receive %ETrace.CallSeqTool.Event{arity: 2, depth: 4, fun: :recur_len, message: [[:list, [5]], [:val, 4]], mod: ETrace.Test, pid: _, return_value: nil, type: :enter}
    assert_receive %ETrace.CallSeqTool.Event{arity: 2, depth: 5, fun: :recur_len, message: [[:list, []], [:val, 5]], mod: ETrace.Test, pid: _, return_value: nil, type: :enter}
    assert_receive %ETrace.CallSeqTool.Event{arity: 2, depth: 5, fun: :recur_len, message: nil, mod: ETrace.Test, pid: _, return_value: 5, type: :exit}
    assert_receive %ETrace.CallSeqTool.Event{arity: 2, depth: 4, fun: :recur_len, message: nil, mod: ETrace.Test, pid: _, return_value: 5, type: :exit}
    assert_receive %ETrace.CallSeqTool.Event{arity: 2, depth: 3, fun: :recur_len, message: nil, mod: ETrace.Test, pid: _, return_value: 5, type: :exit}
    assert_receive %ETrace.CallSeqTool.Event{arity: 2, depth: 2, fun: :recur_len, message: nil, mod: ETrace.Test, pid: _, return_value: 5, type: :exit}
    assert_receive %ETrace.CallSeqTool.Event{arity: 2, depth: 1, fun: :recur_len, message: nil, mod: ETrace.Test, pid: _, return_value: 5, type: :exit}
    assert_receive %ETrace.CallSeqTool.Event{arity: 2, depth: 0, fun: :recur_len, message: nil, mod: ETrace.Test, pid: _, return_value: 5, type: :exit}

    assert_receive {:done_tracing, :stop_command}
    # not expeting more events
    refute_receive(_)
  end

end
