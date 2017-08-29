defmodule ETrace.Tracer.Test do
  use ExUnit.Case
  alias ETrace.{Tracer, Probe, Reporter}
  import ETrace.Matcher
  require ETrace.Clause

  test "new returns a tracer" do
    assert Tracer.new() == %Tracer{}
  end

  test "new accepts a probe shorthand" do
    res = Tracer.new(probe: Probe.new(type: :call))
      |> Tracer.probes()

    assert res == [Probe.new(type: :call)]
  end

  test "add_probe complains if not passed a probe" do
    res = Tracer.new()
      |> Tracer.add_probe(%{})
    assert res == {:error, :not_a_probe}
  end

  test "add_probe adds probe to tracer" do
    res = Tracer.new()
      |> Tracer.add_probe(Probe.new(type: :call))
      |> Tracer.probes()

    assert res == [Probe.new(type: :call)]
  end

  test "add_probe fails if tracer has a probe of the same type" do
    res = Tracer.new()
      |> Tracer.add_probe(Probe.new(type: :call))
      |> Tracer.add_probe(Probe.new(type: :call))

    assert res == {:error, :duplicate_probe_type}
  end

  test "remove_probe removes probe from tracer" do
    res = Tracer.new()
      |> Tracer.add_probe(Probe.new(type: :call))
      |> Tracer.remove_probe(Probe.new(type: :call))
      |> Tracer.probes()

    assert res == []
  end

  test "valid? returns error if not probes have been configured" do
    res = Tracer.new()
      |> Tracer.valid?()

    assert res == {:error, :missing_probes}
  end

  test "valid? return error if probes are invalid" do
    res = Tracer.new()
      |> Tracer.add_probe(Probe.new(type: :call))
      |> Tracer.add_probe(Probe.new(type: :send))
      |> Tracer.valid?()

    assert res == {:error, :invalid_probe, [
      {:error, :missing_processes, Probe.new(type: :call)},
      {:error, :missing_processes, Probe.new(type: :send)}
    ]}
  end

  # Helper
  def test_tracer_proc(opts) do
    receive do
      event ->
        forward_pid = Keyword.get(opts, :forward_to)
        # IO.puts ("tracing handler: forward_pid #{inspect forward_pid} event #{inspect event}")
        if is_pid(forward_pid) do
          send forward_pid, event
        end
        if Keyword.get(opts, :print, false) do
          IO.puts(inspect event)
        end
        test_tracer_proc(opts)
    end
  end

  test "run performs a validation" do
    res = Tracer.new()
      |> Tracer.run()

    assert res == {:error, :missing_probes}
  end

  test "run enables probe and starts tracing and stop ends it" do
    my_pid = self()

    tracer = Tracer.new()
      |> Tracer.add_probe(
            Probe.new(type: :send)
            |> Probe.add_process(self()))


    # Run
    tracer_pid = spawn fn -> test_tracer_proc(forward_to: my_pid) end
    tracer2 = tracer
      |> Tracer.run(tracer: tracer_pid)

    assert tracer == tracer2
    send self(), :foo

    assert_receive(:foo)
    assert_receive({:trace_ts, ^my_pid, :send, :foo, ^my_pid, _})
    refute_receive({:trace_ts, ^my_pid, :send, :foo, ^my_pid, _})

    # Stop
    res = Tracer.stop_run(tracer2)

    assert res == tracer2
    send self(), :foo_one_more_time
    refute_receive({:trace_ts, _, _, _, _, _})

  end

  test "run full call tracing" do
    my_pid = self()

    probe = Probe.new(
                type: :call,
                process: self(),
                match_by: global do Map.new(%{items: [a, b]}) -> message(a, b) end)

    tracer = Tracer.new(probe: probe)

    # Run
    tracer_pid = spawn fn -> test_tracer_proc(forward_to: my_pid) end
    tracer2 = tracer
      |> Tracer.run([tracer: tracer_pid])

    assert tracer == tracer2

    # no match
    Map.new(%{other_key: [1, 2]})
    refute_receive({:trace_ts, ^my_pid, :call,
      {Map, :new, 1}, _, _})

    # valid match - ignore timestamps
    Map.new(%{items: [1, 2]})
    assert_receive({:trace_ts, ^my_pid, :call,
      {Map, :new, 1}, [[:a, 1], [:b, 2]], _})

    res = Tracer.stop_run(tracer2)

    assert res == tracer2

    # not expeting more events
    Map.new(%{items: [1, 2]})
    refute_receive({:trace_ts, _, _, _, _, _})
  end

  test "get_start_cmds generates trace command list" do
    my_pid = self()

    probe = Probe.new(
                type: :call,
                process: my_pid,
                match_by: global do Map.new(%{items: [a, b]}) -> message(a, b) end)

    tracer = Tracer.new(probe: probe)

    tracer_pid = spawn fn -> test_tracer_proc(forward_to: my_pid) end
    [trace_pattern_cmd, trace_cmd] =
      Tracer.get_start_cmds(tracer, tracer: tracer_pid)

    assert trace_pattern_cmd == [
      fun: &:erlang.trace_pattern/3,
      mfa: {Map, :new, 1},
      match_spec: [{[%{items: [:"$1", :"$2"]}], [],
        [message: [[:a, :"$1"], [:b, :"$2"]]]}],
      flag_list: [:global]]

    assert trace_cmd == [
      fun: &:erlang.trace/3,
      pid_port_spec: my_pid,
      how: true,
      flag_list: [{:tracer, tracer_pid}, :call, :arity, :timestamp]]

  end

  test "start and stop tracing" do
    Process.flag(:trap_exit, true)
    my_pid = self()

    probe = Probe.new(
                type: :call,
                process: self(),
                match_by: global do Map.new(%{items: [a, b]}) -> message(a, b) end)

    tracer = Tracer.new(probe: probe)

    tracer_pid = spawn fn -> test_tracer_proc(forward_to: my_pid) end
    tracer2 = Tracer.start(tracer, forward_pid: tracer_pid)

    # no match
    Map.new(%{other_key: [1, 2]})
    refute_receive({:trace_ts, ^my_pid, :call,
      {Map, :new, 1}, _, _})

    # valid match - ignore timestamps
    Map.new(%{items: [1, 2]})
    assert_receive({:trace_ts, ^my_pid, :call,
      {Map, :new, 1}, [[:a, 1], [:b, 2]], _})

    Tracer.stop(tracer2)

    :timer.sleep(50)
    # not expeting more events
    Map.new(%{items: [1, 2]})
    refute_receive({:trace_ts, _, _, _, _, _})
  end

  def local_function(a) do
    :timer.sleep(1)
    a
  end

  test "trace local function" do
    Process.flag(:trap_exit, true)
    my_pid = self()

    probe = Probe.new(
                type: :call,
                process: self(),
                # with_fun: {ETrace.Tracer.Test, :local_function, 1},
                # match_by: local do (a) -> message(a) end)
                match_by: local do ETrace.Tracer.Test.local_function(a) -> message(a) end)

    tracer = Tracer.new(probe: probe)

    tracer2 = Tracer.start(tracer, forward_pid: self())

    :timer.sleep(50)
    # call local_function
    local_function(1)

    assert_receive({:trace_ts, ^my_pid, :call,
      {ETrace.Tracer.Test, :local_function, 1}, [[:a, 1]], _})

    Tracer.stop(tracer2)

    :timer.sleep(50)
    # not expeting more events
    local_function(1)
    refute_receive({:trace_ts, _, _, _, _, _})
  end

  test "trace with a count reporter" do
    Process.flag(:trap_exit, true)
    test_pid = self()
    probe = Probe.new(
                type: :call,
                process: test_pid,
                match_by: local do String.split(a, b) -> message(a, b) end)
                # match_by: local do String.split(string, pattern) -> return_trace(); count(string, pattern) end)
                # match_by: local do ETrace.Tracer.Test.local_function(a) -> return_trace(); count(:max, a)  end)

    tracer = Tracer.new(probe: probe)

    reporter_pid = Reporter.start(count: [report_fun: fn event -> send test_pid, event end])
    tracer2 = Tracer.start(tracer, forward_pid: reporter_pid)

    :timer.sleep(50)

    # call local_function
    # 1..10 |> Enum.each(fn _ -> local_function(Enum.random(1..20)) end)

    # Map.new(%{a: 1})
    # Map.new(%{a: 1})
    # Map.new(%{a: 8})
    # Map.new(%{a: 8})
    # Map.new(%{a: 8})
    # Map.new(%{"foo": [1, 2, 3]})
    # Map.new(%{"foo": [1, 2, 3]})
    # Map.new(%{"foo": [1, 2, 3]})
    # Map.new(%{"foo": [1, 2, 3]})
    # Map.new(%{"foo": [1, 2, 3]})
    # Map.new(%{"foo": [1, 2, 3]})
    # Map.new(%{"foo": [1, 2, 3]})

    String.split("hello world", ",")
    String.split("x,y", ",")
    String.split("z,y", ",")
    String.split("x,y", ",")
    String.split("z,y", ",")
    String.split("x,y", ",")

    :timer.sleep(50)
    Reporter.stop(reporter_pid)

    assert_receive %ETrace.CountReporter.Event{counts:
      [{[a: "\"hello world\"", b: "\",\""], 1},
       {[a: "\"z,y\"", b: "\",\""], 2},
       {[a: "\"x,y\"", b: "\",\""], 3}]}

    Tracer.stop(tracer2)

    assert_receive({:EXIT, _, {:done_tracing, :stop_command}})
    assert_receive({:EXIT, _, :done_reporting})
    # not expeting more events
    refute_receive(_)
  end

  def recur_len([], acc), do: acc
  def recur_len([_h | t], acc), do: recur_len(t, acc + 1)

  test "trace with a duration reporter" do
    Process.flag(:trap_exit, true)
    test_pid = self()

    probe = Probe.new(
                type: :call,
                process: test_pid,
                match_by: local do ETrace.Tracer.Test.recur_len(list, val) -> return_trace(); message(list, val) end)

    tracer = Tracer.new(probe: probe)

    reporter_pid = Reporter.start(duration:
                                  [report_fun: fn event -> send test_pid, event end])
    tracer2 = Tracer.start(tracer, forward_pid: reporter_pid)

    :timer.sleep(50)

    recur_len([1, 2, 3, 4, 5], 0)
    recur_len([1, 2, 3, 5], 2)

    assert_receive(%{pid: ^test_pid, mod: ETrace.Tracer.Test, fun: :recur_len,
        arity: 2, duration: _, message: [[:list, [1, 2, 3, 4, 5]], [:val, 0]]})
    assert_receive(%{pid: ^test_pid, mod: ETrace.Tracer.Test, fun: :recur_len,
        arity: 2, duration: _, message: [[:list, [1, 2, 3, 5]], [:val, 2]]})

    Tracer.stop(tracer2)

    assert_receive({:EXIT, _, {:done_tracing, :stop_command}})
    # not expeting more events
    refute_receive(_)
  end

  test "trace with a display reporter" do
    Process.flag(:trap_exit, true)
    test_pid = self()
    probe = Probe.new(
                type: :call,
                process: test_pid,
                match_by: local do String.split(string, pattern) -> return_trace(); message(string, pattern) end)

    tracer = Tracer.new(probe: probe)

    reporter_pid = Reporter.start(display: [report_fun: fn event -> send test_pid, event end])
    tracer2 = Tracer.start(tracer, forward_pid: reporter_pid)

    :timer.sleep(50)

    String.split("a, add", " ")
    String.split("a,b", ",")
    String.split("c,b", ",")
    String.split("a,b", ",")
    String.split("c,b", ",")
    String.split("a,b", ",")

    assert_receive(%{pid: ^test_pid, mod: String, fun: :split, arity: 2,
                     message: [[:string, "a, add"], [:pattern, " "]], ts: _})
    assert_receive(%{pid: ^test_pid, mod: String, fun: :split, arity: 2,
                     return_value: ["a,", "add"], ts: _})
    assert_receive(%{pid: ^test_pid, mod: String, fun: :split, arity: 2,
                     message: [[:string, "a,b"], [:pattern, ","]], ts: _})
    assert_receive(%{pid: ^test_pid, mod: String, fun: :split, arity: 2,
                     return_value: ["a", "b"], ts: _})
    assert_receive(%{pid: ^test_pid, mod: String, fun: :split, arity: 2,
                     message: [[:string, "c,b"], [:pattern, ","]], ts: _})
    assert_receive(%{pid: ^test_pid, mod: String, fun: :split, arity: 2,
                     return_value: ["c", "b"], ts: _})
    assert_receive(%{pid: ^test_pid, mod: String, fun: :split, arity: 2,
                    message: [[:string, "a,b"], [:pattern, ","]], ts: _})
    assert_receive(%{pid: ^test_pid, mod: String, fun: :split, arity: 2,
                    return_value: ["a", "b"], ts: _})
    assert_receive(%{pid: ^test_pid, mod: String, fun: :split, arity: 2,
                     message: [[:string, "c,b"], [:pattern, ","]], ts: _})
    assert_receive(%{pid: ^test_pid, mod: String, fun: :split, arity: 2,
                     return_value: ["c", "b"], ts: _})
    assert_receive(%{pid: ^test_pid, mod: String, fun: :split, arity: 2,
                    message: [[:string, "a,b"], [:pattern, ","]], ts: _})
    assert_receive(%{pid: ^test_pid, mod: String, fun: :split, arity: 2,
                    return_value: ["a", "b"], ts: _})

    Tracer.stop(tracer2)

    # not expeting more events
    assert_receive({:EXIT, _, {:done_tracing, :stop_command}})
    refute_receive(_)
  end

  test "trace with a call_seq reporter" do
    Process.flag(:trap_exit, true)
    test_pid = self()
    probe = Probe.new(
                type: :call,
                process: test_pid,
                match_by: local do ETrace.Tracer.Test.recur_len(list, val) -> return_trace(); message(list, val) end)
                # match_by: local do _ -> return_trace(); message(:"$_") end)

    tracer = Tracer.new(probe: probe)

    # reporter_pid = Reporter.start(call_seq: [])
    reporter_pid = Reporter.start(call_seq: [report_fun: fn event -> send test_pid, event end])
    tracer2 = Tracer.start(tracer, forward_pid: reporter_pid)

    :timer.sleep(50)

    # IO.puts("Hello World")
    recur_len([1, 2, 3, 4, 5], 0)

    :timer.sleep(50)
    Reporter.stop(reporter_pid)

    assert_receive %ETrace.CallSeqReporter.Event{arity: 2, depth: 0, fun: :recur_len, message: [[:list, [1, 2, 3, 4, 5]], [:val, 0]], mod: ETrace.Tracer.Test, pid: _, return_value: nil, type: :enter}
    assert_receive %ETrace.CallSeqReporter.Event{arity: 2, depth: 1, fun: :recur_len, message: [[:list, [2, 3, 4, 5]], [:val, 1]], mod: ETrace.Tracer.Test, pid: _, return_value: nil, type: :enter}
    assert_receive %ETrace.CallSeqReporter.Event{arity: 2, depth: 2, fun: :recur_len, message: [[:list, [3, 4, 5]], [:val, 2]], mod: ETrace.Tracer.Test, pid: _, return_value: nil, type: :enter}
    assert_receive %ETrace.CallSeqReporter.Event{arity: 2, depth: 3, fun: :recur_len, message: [[:list, [4, 5]], [:val, 3]], mod: ETrace.Tracer.Test, pid: _, return_value: nil, type: :enter}
    assert_receive %ETrace.CallSeqReporter.Event{arity: 2, depth: 4, fun: :recur_len, message: [[:list, [5]], [:val, 4]], mod: ETrace.Tracer.Test, pid: _, return_value: nil, type: :enter}
    assert_receive %ETrace.CallSeqReporter.Event{arity: 2, depth: 5, fun: :recur_len, message: [[:list, []], [:val, 5]], mod: ETrace.Tracer.Test, pid: _, return_value: nil, type: :enter}
    assert_receive %ETrace.CallSeqReporter.Event{arity: 2, depth: 5, fun: :recur_len, message: nil, mod: ETrace.Tracer.Test, pid: _, return_value: 5, type: :exit}
    assert_receive %ETrace.CallSeqReporter.Event{arity: 2, depth: 4, fun: :recur_len, message: nil, mod: ETrace.Tracer.Test, pid: _, return_value: 5, type: :exit}
    assert_receive %ETrace.CallSeqReporter.Event{arity: 2, depth: 3, fun: :recur_len, message: nil, mod: ETrace.Tracer.Test, pid: _, return_value: 5, type: :exit}
    assert_receive %ETrace.CallSeqReporter.Event{arity: 2, depth: 2, fun: :recur_len, message: nil, mod: ETrace.Tracer.Test, pid: _, return_value: 5, type: :exit}
    assert_receive %ETrace.CallSeqReporter.Event{arity: 2, depth: 1, fun: :recur_len, message: nil, mod: ETrace.Tracer.Test, pid: _, return_value: 5, type: :exit}
    assert_receive %ETrace.CallSeqReporter.Event{arity: 2, depth: 0, fun: :recur_len, message: nil, mod: ETrace.Tracer.Test, pid: _, return_value: 5, type: :exit}

    Tracer.stop(tracer2)

    assert_receive({:EXIT, _, {:done_tracing, :stop_command}})
    assert_receive({:EXIT, _, :done_reporting})
    # not expeting more events
    refute_receive(_)
  end

end
