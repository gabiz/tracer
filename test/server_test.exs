defmodule ETrace.ServerTest do
  use ExUnit.Case
  alias ETrace.{Server, Probe}
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

  test "add_probe() fails when not passing a probe" do
    {:ok, _} = Server.start()
    res = Server.add_probe(:foo)
    assert res == {:error, :not_a_probe}
  end

  test "add_probe() stores the probe in tracer" do
    {:ok, _} = Server.start()
    probe = Probe.new(type: :call, process: self())

    res = Server.add_probe(probe)
    assert res == :ok

    %{tracer: %{probes: probes}} = :sys.get_state(ETrace.Server, 100)
    assert probes == [probe]
  end

  test "remove_probe() removes a probe from tracer" do
    {:ok, _} = Server.start()
    probe = Probe.new(type: :call, process: self())
    :ok = Server.add_probe(probe)

    res = Server.remove_probe(probe)
    assert res == :ok

    %{tracer: %{probes: probes}} = :sys.get_state(ETrace.Server, 100)
    assert probes == []
  end

  test "remove_probe() does nothing if probe is not found" do
    {:ok, _} = Server.start()
    probe = Probe.new(type: :call, process: self())
    :ok = Server.add_probe(probe)
    state = :sys.get_state(ETrace.Server, 100)

    res = Server.remove_probe(Probe.new(type: :procs, process: self()))
    assert res == :ok

    new_state = :sys.get_state(ETrace.Server, 100)
    assert new_state == state
  end

  test "clear_probes() removes all probes" do
    {:ok, _} = Server.start()
    probe = Probe.new(type: :call, process: self())
    :ok = Server.add_probe(probe)
    probe2 = Probe.new(type: :procs, process: self())
    :ok = Server.add_probe(probe2)

    res = Server.clear_probes()
    assert res == :ok

    %{tracer: %{probes: probes}} = :sys.get_state(ETrace.Server, 100)
    assert probes == []
  end

  test "start_trace() fails if no probes have been configured" do
    {:ok, _} = Server.start()
    res = Server.start_trace([])
    assert res == {:error, :missing_probes}
  end

  test "add_probe() fails if probe is not complete" do
    {:ok, _} = Server.start()
    probe = Probe.new(type: :call)
    res = Server.add_probe(probe)
    assert res == {:error, :missing_processes}

    %{tracer: %{probes: probes}} = :sys.get_state(ETrace.Server, 100)
    assert probes == []
  end

  test "start_trace() starts a trace" do
    test_pid = self()
    {:ok, _} = Server.start()
    probe = Probe.new(type: :call,
                      process: self(),
                      match_by: local do Map.new(a) -> message(a) end)
    :ok = Server.add_probe(probe)

    res = Server.start_trace(display: [], forward_to: test_pid)
    assert res == :ok

    state = :sys.get_state(ETrace.Server, 100)
    %{tracing: tracing,
      reporter_pid: reporter_pid,
      tracer: %{agent_pids: [agent_pid],
                probes: [%{process_list: [^test_pid]}]}} = state
    assert tracing
    assert is_pid(reporter_pid)
    assert Process.alive?(reporter_pid)
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

  test "stop_trace() stops tracing" do
    test_pid = self()
    {:ok, _} = Server.start()
    probe = Probe.new(type: :call,
                      process: self(),
                      match_by: local do Map.new(a) -> message(a) end)
    :ok = Server.add_probe(probe)
    # :ok = Server.start_trace(display: [], forward_to: test_pid)
    :ok = Server.start_trace(display: [], forward_to: test_pid)

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
    res = Server.stop_trace()
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

  test "start_trace() allows to override tracing limits" do
    test_pid = self()
    {:ok, _} = Server.start()
    probe = Probe.new(type: :call,
                      process: self(),
                      match_by: local do Map.new(a) -> message(a) end)
    :ok = Server.add_probe(probe)

    :ok = Server.start_trace(max_message_count: 1,
                             display: [], forward_to: test_pid)

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

    # Process.flag(:trap_exit, true)
    test_pid = self()
    {:ok, _} = Server.start()
    probe = Probe.new(type: :call,
                      process: :all,
                      match_by: local do Map.new(a) -> message(a) end)
    :ok = Server.add_probe(probe)

    :ok = Server.start_trace(nodes: remote_node_a,
                             max_message_count: 1,
                             display: [], forward_to: test_pid)

    :timer.sleep(500)
    #  Map.new(%{})
     assert_receive %ETrace.EventCall{mod: Map, fun: :new, arity: 1,
           message: [[:a, %{}]], pid: _, ts: _}

     assert_receive {:done_tracing, :max_message_count, 1}
  end
end
