defmodule ETrace.Server.Test do
  use ExUnit.Case
  alias ETrace.{Server, Probe, Tool}
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

  test "start() creates server" do
    {:ok, pid} = Server.start()
    assert is_pid(pid)
    registered_pid = Process.whereis(ETrace.Server)
    assert registered_pid != nil
    assert registered_pid == pid
  end

  test "start() fails if server already started" do
    {:ok, pid} = Server.start()
    {:error, {:already_started, server_pid}} = Server.start()
    assert pid == server_pid
  end

  test "stop() stops a running server" do
    {:ok, pid} = Server.start()
    assert Process.alive?(pid)
    Server.stop()
    refute Process.alive?(pid)
  end

  test "start_tool() starts a trace" do
    test_pid = self()
    {:ok, _} = Server.start()
    probe = Probe.new(type: :call,
                      process: self(),
                      match_by: local do Map.new(a) -> message(a) end)

    tool = Tool.new(:display, forward_to: test_pid, probe: probe)
    :ok = Server.start_tool(tool)

    state = :sys.get_state(ETrace.Server, 100)
    %{tracing: tracing,
      tool_server_pid: tool_server_pid,
      agent_pids: [agent_pid],
      probes: [%{process_list: [^test_pid]}]} = state
    assert tracing
    assert is_pid(tool_server_pid)
    assert Process.alive?(tool_server_pid)
    assert is_pid(agent_pid)
    assert Process.alive?(agent_pid)

    :timer.sleep(50) # avoid the test from bailing too quickly
    res = :erlang.trace_info(test_pid, :flags)
    assert res == {:flags, [:arity, :call, :timestamp]}
    res = :erlang.trace_info({Map, :new, 1}, :all)
    assert res == {:all,
                  [traced: :local,
                  match_spec: [{[:"$1"], [], [message: [[:a, :"$1"]]]}],
                  meta: false,
                  meta_match_spec: false,
                  call_time: false,
                  call_count: false]}

    # test a trace event
    Map.new(%{})
    assert_receive %ETrace.EventCall{mod: Map, fun: :new, arity: 1,
          message: [[:a, %{}]], pid: ^test_pid, ts: _}
  end

  test "stop_tool() stops tracing" do
    test_pid = self()
    {:ok, _} = Server.start()
    probe = Probe.new(type: :call,
                      process: self(),
                      match_by: local do Map.new(a) -> message(a) end)
    tool = Tool.new(:display, forward_to: test_pid, probe: probe)
    :ok = Server.start_tool(tool)

    # check tracing is enabled
    :timer.sleep(50) # avoid the test from bailing too quickly
    res = :erlang.trace_info(test_pid, :flags)
    assert res == {:flags, [:arity, :call, :timestamp]}
    res = :erlang.trace_info({Map, :new, 1}, :all)
    assert res == {:all,
                  [traced: :local,
                  match_spec: [{[:"$1"], [], [message: [[:a, :"$1"]]]}],
                  meta: false,
                  meta_match_spec: false,
                  call_time: false,
                  call_count: false]}

    assert_receive :started_tracing
    res = Server.stop_tool()
    assert res == :ok

    :timer.sleep(50) # avoid the test from bailing too quickly
    res = :erlang.trace_info(test_pid, :flags)
    assert res == {:flags, []}
    res = :erlang.trace_info({Map, :new, 1}, :all)
    assert res == {:all, false}

    assert_receive {:done_tracing, :stop_command}
    # no trace events should be received
    Map.new(%{})
    refute_receive(_)
  end

  test "start_tool() allows to override tracing limits" do
    test_pid = self()
    {:ok, _} = Server.start()
    probe = Probe.new(type: :call,
                      process: self(),
                      match_by: local do Map.new(a) -> message(a) end)

    tool = Tool.new(:display, forward_to: test_pid, probe: probe,
                    max_message_count: 1)
    :ok = Server.start_tool(tool)

    # :ok = Server.add_probe(probe)
    # :ok = Server.start_trace(max_message_count: 1,
    #                          display: [], forward_to: test_pid)

    :timer.sleep(50)
     Map.new(%{})
     assert_receive %ETrace.EventCall{mod: Map, fun: :new, arity: 1,
           message: [[:a, %{}]], pid: ^test_pid, ts: _}

     assert_receive {:done_tracing, :max_message_count, 1}
  end

  @tag :remote_node
  test "start_trace() allows to start on a remote node" do
    :net_kernel.start([:"local2@127.0.0.1"])

    remote_node = "remote#{Enum.random(1..100)}@127.0.0.1"
    remote_node_a = String.to_atom(remote_node)
    spawn(fn ->
        System.cmd("elixir", ["--name", remote_node,
            "-e", "for _ <- 1..200 do Map.new(%{}); :timer.sleep(25) end"])
    end)

    :timer.sleep(500)
    # check if remote node is up
    case :net_adm.ping(remote_node_a) do
      :pang ->
        assert false
      :pong -> :ok
    end

    test_pid = self()
    {:ok, _} = Server.start()
    probe = Probe.new(type: :call,
                      process: :all,
                      match_by: local do Map.new(a) -> message(a) end)

    tool = Tool.new(:display, nodes: [remote_node_a], forward_to: test_pid, probe: probe)
    :ok = Server.start_tool(tool)

    # :ok = Server.add_probe(probe)
    #
    # :ok = Server.start_trace(nodes: remote_node_a,
    #                          max_message_count: 1,
    #                          display: [], forward_to: test_pid)

    :timer.sleep(500)
     assert_receive %ETrace.EventCall{mod: Map, fun: :new, arity: 1,
           message: [[:a, %{}]], pid: _, ts: _}

    #  assert_receive {:done_tracing, :max_message_count, 1}
  end

  test "trace with a count tool" do
    test_pid = self()

    {:ok, _} = Server.start()
    probe = Probe.new(
                type: :call,
                process: test_pid,
                match_by: local do String.split(a, b) -> message(a, b) end)

    tool = Tool.new(:count, forward_to: test_pid, probe: probe)
    :ok = Server.start_tool(tool)

    :timer.sleep(50)

    String.split("hello world", ",")
    String.split("x,y", ",")
    String.split("z,y", ",")
    String.split("x,y", ",")
    String.split("z,y", ",")
    String.split("x,y", ",")

    assert_receive :started_tracing
    res = Server.stop_tool()
    assert res == :ok

    assert_receive %ETrace.CountTool.Event{counts:
      [{[a: "hello world", b: ","], 1},
       {[a: "z,y", b: ","], 2},
       {[a: "x,y", b: ","], 3}]}


    assert_receive {:done_tracing, :stop_command}
    # not expeting more events
    refute_receive(_)
  end

  def recur_len([], acc), do: acc
  def recur_len([_h | t], acc), do: recur_len(t, acc + 1)

  test "trace with a duration tool" do
    test_pid = self()

    {:ok, _} = Server.start()
    probe = Probe.new(
                type: :call,
                process: test_pid,
                match_by: local do ETrace.Server.Test.recur_len(list, val) -> return_trace(); message(list, val) end)

    tool = Tool.new(:duration, forward_to: test_pid, probe: probe)
    :ok = Server.start_tool(tool)

    assert_receive :started_tracing

    recur_len([1, 2, 3, 4, 5], 0)
    recur_len([1, 2, 3, 5], 2)

    assert_receive(%{pid: ^test_pid, mod: ETrace.Server.Test, fun: :recur_len,
        arity: 2, duration: _, message: [[:list, [1, 2, 3, 4, 5]], [:val, 0]]})
    assert_receive(%{pid: ^test_pid, mod: ETrace.Server.Test, fun: :recur_len,
        arity: 2, duration: _, message: [[:list, [1, 2, 3, 5]], [:val, 2]]})

    res = Server.stop_tool()
    assert res == :ok

    assert_receive {:done_tracing, :stop_command}
    # not expeting more events
    refute_receive(_)
  end

  test "trace with a display tool" do
    test_pid = self()

    {:ok, _} = Server.start()
    probe = Probe.new(
                type: :call,
                process: test_pid,
                match_by: local do String.split(string, pattern) -> return_trace(); message(string, pattern) end)

    tool = Tool.new(:display, forward_to: test_pid, probe: probe)
    :ok = Server.start_tool(tool)

    assert_receive :started_tracing

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

    res = Server.stop_tool()
    assert res == :ok

    assert_receive {:done_tracing, :stop_command}
    # not expeting more events
    refute_receive(_)
  end

  test "trace with a call_seq tool" do
    test_pid = self()

    {:ok, _} = Server.start()
    probe = Probe.new(
                type: :call,
                process: test_pid,
                match_by: local do ETrace.Server.Test.recur_len(list, val) -> return_trace(); message(list, val) end)

    tool = Tool.new(:call_seq, forward_to: test_pid, probe: probe)
    :ok = Server.start_tool(tool)

    assert_receive :started_tracing

    recur_len([1, 2, 3, 4, 5], 0)

    :timer.sleep(10)
    res = Server.stop_tool()
    assert res == :ok

    assert_receive %ETrace.CallSeqTool.Event{arity: 2, depth: 0, fun: :recur_len, message: [[:list, [1, 2, 3, 4, 5]], [:val, 0]], mod: ETrace.Server.Test, pid: _, return_value: nil, type: :enter}
    assert_receive %ETrace.CallSeqTool.Event{arity: 2, depth: 1, fun: :recur_len, message: [[:list, [2, 3, 4, 5]], [:val, 1]], mod: ETrace.Server.Test, pid: _, return_value: nil, type: :enter}
    assert_receive %ETrace.CallSeqTool.Event{arity: 2, depth: 2, fun: :recur_len, message: [[:list, [3, 4, 5]], [:val, 2]], mod: ETrace.Server.Test, pid: _, return_value: nil, type: :enter}
    assert_receive %ETrace.CallSeqTool.Event{arity: 2, depth: 3, fun: :recur_len, message: [[:list, [4, 5]], [:val, 3]], mod: ETrace.Server.Test, pid: _, return_value: nil, type: :enter}
    assert_receive %ETrace.CallSeqTool.Event{arity: 2, depth: 4, fun: :recur_len, message: [[:list, [5]], [:val, 4]], mod: ETrace.Server.Test, pid: _, return_value: nil, type: :enter}
    assert_receive %ETrace.CallSeqTool.Event{arity: 2, depth: 5, fun: :recur_len, message: [[:list, []], [:val, 5]], mod: ETrace.Server.Test, pid: _, return_value: nil, type: :enter}
    assert_receive %ETrace.CallSeqTool.Event{arity: 2, depth: 5, fun: :recur_len, message: nil, mod: ETrace.Server.Test, pid: _, return_value: 5, type: :exit}
    assert_receive %ETrace.CallSeqTool.Event{arity: 2, depth: 4, fun: :recur_len, message: nil, mod: ETrace.Server.Test, pid: _, return_value: 5, type: :exit}
    assert_receive %ETrace.CallSeqTool.Event{arity: 2, depth: 3, fun: :recur_len, message: nil, mod: ETrace.Server.Test, pid: _, return_value: 5, type: :exit}
    assert_receive %ETrace.CallSeqTool.Event{arity: 2, depth: 2, fun: :recur_len, message: nil, mod: ETrace.Server.Test, pid: _, return_value: 5, type: :exit}
    assert_receive %ETrace.CallSeqTool.Event{arity: 2, depth: 1, fun: :recur_len, message: nil, mod: ETrace.Server.Test, pid: _, return_value: 5, type: :exit}
    assert_receive %ETrace.CallSeqTool.Event{arity: 2, depth: 0, fun: :recur_len, message: nil, mod: ETrace.Server.Test, pid: _, return_value: 5, type: :exit}

    assert_receive {:done_tracing, :stop_command}

    # not expeting more events
    refute_receive(_)
  end

end
