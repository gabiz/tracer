defmodule ETrace.HandlerAgent.Test do
  use ExUnit.Case
  alias ETrace.HandlerAgent

  test "start() creates handler_agent process" do
    pid = HandlerAgent.start()
    assert is_pid(pid)
    assert Process.alive?(pid)
  end

  test "start() creates pid_handler process" do
    pid = HandlerAgent.start()
    send pid, {:get_handler_pid, self()}
    assert_receive {:handler_pid, handler_pid}
    assert is_pid(handler_pid)
    assert Process.alive?(handler_pid)
  end

  test "start() stores the handler_pid options" do
    pid = HandlerAgent.start(max_message_count: 123,
                            max_message_queue_size: 456,
                            event_callback: &Map.new/1)

    send pid, {:get_pid_handler_opts, self()}
    assert_receive {:pid_handler_opts, pid_handler_opts}
    assert Keyword.get(pid_handler_opts, :max_message_count) == 123
    assert Keyword.get(pid_handler_opts, :max_message_queue_size) == 456
    assert Keyword.get(pid_handler_opts, :event_callback) == &Map.new/1
  end

  test "agent_handler process finishes after timeout" do
    Process.flag(:trap_exit, true)
    pid = HandlerAgent.start(max_tracing_time: 50)
    assert Process.alive?(pid)
    assert_receive({:EXIT, ^pid, {:done_tracing, :tracing_timeout}})
    refute Process.alive?(pid)
  end

  test "agent_handler process finishes after message count hits limit" do
    Process.flag(:trap_exit, true)
    pid = HandlerAgent.start(max_message_count: 1)
    assert Process.alive?(pid)

    send pid, {:get_handler_pid, self()}
    assert_receive {:handler_pid, handler_pid}
    assert Process.alive?(handler_pid)

    send handler_pid, {:trace, :foo}

    assert_receive({:EXIT, ^pid, {:done_tracing, :max_message_count}})
    refute Process.alive?(pid)
    refute Process.alive?(handler_pid)
  end

  test "agent_handler process finishes after max queue size triggers" do
    Process.flag(:trap_exit, true)
    pid = HandlerAgent.start(max_message_queue_size: 1,
                             event_callback: fn _event ->
                                :timer.sleep(20);
                                :ok end)
    assert Process.alive?(pid)

    send pid, {:get_handler_pid, self()}
    assert_receive {:handler_pid, handler_pid}
    assert Process.alive?(handler_pid)

    send handler_pid, {:trace, :foo}
    send handler_pid, {:trace, :bar}
    send handler_pid, {:trace, :foo_bar}

    assert_receive({:EXIT, ^pid, {:done_tracing, :message_queue_size, _}})
    refute Process.alive?(pid)
    refute Process.alive?(handler_pid)
  end

  test "stop() aborts the tracing and processes terminate" do
    Process.flag(:trap_exit, true)
    pid = HandlerAgent.start()
    assert Process.alive?(pid)

    send pid, {:get_handler_pid, self()}
    assert_receive {:handler_pid, handler_pid}
    assert Process.alive?(handler_pid)

    HandlerAgent.stop(pid)

    assert_receive({:EXIT, ^pid, {:done_tracing, :stop_command}})
    refute Process.alive?(pid)
    refute Process.alive?(handler_pid)
  end
end
