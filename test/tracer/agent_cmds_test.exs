defmodule Tracer.AgentCmds.Test do
  use ExUnit.Case
  alias Tracer.{AgentCmds, Probe}
  import Tracer.Matcher

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

  test "run enables probe and starts tracing and stop ends it" do
    my_pid = self()

    probe = Probe.new(type: :send) |> Probe.add_process(self())

    # Run
    tracer_pid = spawn fn -> test_tracer_proc(forward_to: my_pid) end
    res = AgentCmds.run([probe], tracer: tracer_pid)
    assert is_list(res) and length(res) > 0

    send self(), :foo

    assert_receive(:foo)
    assert_receive({:trace_ts, ^my_pid, :send, :foo, ^my_pid, _})
    refute_receive({:trace_ts, ^my_pid, :send, :foo, ^my_pid, _})

    # Stop
    res = AgentCmds.stop_run()
    assert res > 0

    send self(), :foo_one_more_time
    refute_receive({:trace_ts, _, _, _, _, _})

  end

  test "run full call tracing" do
    my_pid = self()

    probe = Probe.new(
                type: :call,
                process: self(),
                match: global do Map.new(%{items: [a, b]}) -> message(a, b) end)

    # Run
    tracer_pid = spawn fn -> test_tracer_proc(forward_to: my_pid) end
    res = AgentCmds.run([probe], tracer: tracer_pid)
    assert is_list(res) and length(res) > 0

    # no match
    Map.new(%{other_key: [1, 2]})
    refute_receive({:trace_ts, ^my_pid, :call,
      {Map, :new, 1}, _, _})

    # valid match - ignore timestamps
    Map.new(%{items: [1, 2]})
    assert_receive({:trace_ts, ^my_pid, :call,
      {Map, :new, 1}, [[:a, 1], [:b, 2]], _})

    res = AgentCmds.stop_run()

    assert res > 0

    # not expeting more events
    Map.new(%{items: [1, 2]})
    refute_receive({:trace_ts, _, _, _, _, _})
  end

  test "get_start_cmds generates trace command list" do
    my_pid = self()

    probe = Probe.new(
                type: :call,
                process: my_pid,
                match: global do Map.new(%{items: [a, b]}) -> message(a, b) end)

    tracer_pid = spawn fn -> test_tracer_proc(forward_to: my_pid) end
    [trace_pattern_cmd, trace_cmd] =
      AgentCmds.get_start_cmds([probe], tracer: tracer_pid)

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
                match: global do Map.new(%{items: [a, b]}) -> message(a, b) end)

    tracer_pid = spawn fn -> test_tracer_proc(forward_to: my_pid) end
    agent_pids = AgentCmds.start(nil, [probe], forward_pid: tracer_pid)
    assert is_list(agent_pids) and length(agent_pids) > 0

    # no match
    Map.new(%{other_key: [1, 2]})
    refute_receive({:trace_ts, ^my_pid, :call,
      {Map, :new, 1}, _, _})

    # valid match - ignore timestamps
    Map.new(%{items: [1, 2]})
    assert_receive({:trace_ts, ^my_pid, :call,
      {Map, :new, 1}, [[:a, 1], [:b, 2]], _})

    :ok = AgentCmds.stop(agent_pids)

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
                # with_fun: {Tracer.Tracer.Test, :local_function, 1},
                # match: local do (a) -> message(a) end)
                match: local do Tracer.AgentCmds.Test.local_function(a) -> message(a) end)

    agent_pids = AgentCmds.start(nil, [probe], forward_pid: self())
    assert is_list(agent_pids) and length(agent_pids) > 0

    :timer.sleep(50)
    # call local_function
    local_function(1)

    assert_receive({:trace_ts, ^my_pid, :call,
      {Tracer.AgentCmds.Test, :local_function, 1}, [[:a, 1]], _})

    :ok = AgentCmds.stop(agent_pids)

    :timer.sleep(50)
    # not expeting more events
    local_function(1)
    refute_receive({:trace_ts, _, _, _, _, _})
  end

end
