defmodule ETrace.PidHandler.Test do
  use ExUnit.Case

  alias ETrace.PidHandler

  test "start raises an error when no callback is passed" do
    assert_raise ArgumentError, "missing event_callback configuration", fn ->
      PidHandler.start(max_message_count: 1)
    end
  end

  test "start spawn a process and returns its pid" do
    pid = PidHandler.start(event_callback: fn _event -> :ok end)
    assert is_pid(pid)
    assert Process.alive?(pid)
  end

  test "stop causes the process to end with a normal status" do
    Process.flag(:trap_exit, true)
    pid = PidHandler.start(event_callback: fn _event -> :ok end)
    assert Process.alive?(pid)
    PidHandler.stop(pid)
    assert_receive({:EXIT, ^pid, :normal})
    refute Process.alive?(pid)
  end

  test "max_message_count triggers when too many events are received" do
    Process.flag(:trap_exit, true)
    pid = PidHandler.start(max_message_count: 2,
                           event_callback: fn _event -> :ok end)
    assert Process.alive?(pid)
    send pid, {:trace, :foo}
    send pid, {:trace_ts, :bar}
    assert_receive({:EXIT, ^pid, :max_message_count})
    refute Process.alive?(pid)
  end

  test "unrecognized messages are discarded to avoid queue from filling up" do
    Process.flag(:trap_exit, true)
    pid = PidHandler.start(max_message_count: 1,
                           event_callback: fn _event -> :ok end)
    assert Process.alive?(pid)
    for i <- 1..100, do: send pid, {:not_expeted_message, i}
    case Process.info(self(), :message_queue_len) do
      {:message_queue_len, len} -> assert len == 0
      error -> assert error
    end
  end

  test "callback is invoked when a trace event is received" do
    Process.flag(:trap_exit, true)
    test_pid = self()
    pid = PidHandler.start(event_callback: fn event ->
       send test_pid, event
       :ok
    end)
    assert Process.alive?(pid)
    for i <- 1..100, do: send pid, {:trace, i}
    for i <- 1..100, do: assert_receive {:trace, ^i}
  end

  test "process exits if callback does not return :ok" do
    Process.flag(:trap_exit, true)
    pid = PidHandler.start(event_callback: fn _event -> :not_ok end)
    assert Process.alive?(pid)
    send pid, {:trace, :foo}
    assert_receive({:EXIT, ^pid, :not_ok})
    refute Process.alive?(pid)
  end

  test "process exits if too many messages wait in mailbox" do
    Process.flag(:trap_exit, true)
    pid = PidHandler.start(max_message_queue_size: 10,
                           event_callback: fn _event ->
                              :timer.sleep(20);
                              :ok end)
    assert Process.alive?(pid)
    for i <- 1..11, do: send pid, {:trace, i}
    case Process.info(pid, :message_queue_len) do
      {:message_queue_len, len} -> assert len >= 10
      _ -> :ok
    end
    assert_receive({:EXIT, ^pid, {:message_queue_size, 11}})
    refute Process.alive?(pid)
  end
end
