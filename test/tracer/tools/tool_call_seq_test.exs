defmodule Tracer.Tool.CallSeq.Test do
  use ExUnit.Case
  alias __MODULE__
  alias Tracer.Tool.CallSeq
  import Tracer

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

  def recur_len([], acc), do: acc
  def recur_len([_h | t], acc), do: recur_len(t, acc + 1)

  test "CallSeq with start_mach module, show args" do
    test_pid = self()

    res = start_tool(CallSeq,
                     process: test_pid,
                     show_args: true,
                     show_return: true,
                     max_depth: 16,
                    #  ignore_recursion: true,
                     forward_to: test_pid,
                    #  start_fun: &Test.recur_len/2)
                     start_match: Test)
    assert res == :ok

    :timer.sleep(10)

    assert_receive :started_tracing

    recur_len([1, 2, 3, 4, 5], 0)

    :timer.sleep(10)
    res = stop_tool()
    assert res == :ok

    assert_receive %CallSeq.Event{arity: 2, depth: 0, fun: :recur_len, message: [[[1, 2, 3, 4, 5], 0]], mod: Test, pid: _, return_value: nil, type: :enter}
    assert_receive %CallSeq.Event{arity: 2, depth: 1, fun: :recur_len, message: [[[2, 3, 4, 5], 1]], mod: Test, pid: _, return_value: nil, type: :enter}
    assert_receive %CallSeq.Event{arity: 2, depth: 2, fun: :recur_len, message: [[[3, 4, 5], 2]], mod: Test, pid: _, return_value: nil, type: :enter}
    assert_receive %CallSeq.Event{arity: 2, depth: 3, fun: :recur_len, message: [[[4, 5], 3]], mod: Test, pid: _, return_value: nil, type: :enter}
    assert_receive %CallSeq.Event{arity: 2, depth: 4, fun: :recur_len, message: [[[5], 4]], mod: Test, pid: _, return_value: nil, type: :enter}
    assert_receive %CallSeq.Event{arity: 2, depth: 5, fun: :recur_len, message: [[[], 5]], mod: Test, pid: _, return_value: nil, type: :enter}
    assert_receive %CallSeq.Event{arity: 2, depth: 5, fun: :recur_len, message: nil, mod: Test, pid: _, return_value: 5, type: :exit}
    assert_receive %CallSeq.Event{arity: 2, depth: 4, fun: :recur_len, message: nil, mod: Test, pid: _, return_value: 5, type: :exit}
    assert_receive %CallSeq.Event{arity: 2, depth: 3, fun: :recur_len, message: nil, mod: Test, pid: _, return_value: 5, type: :exit}
    assert_receive %CallSeq.Event{arity: 2, depth: 2, fun: :recur_len, message: nil, mod: Test, pid: _, return_value: 5, type: :exit}
    assert_receive %CallSeq.Event{arity: 2, depth: 1, fun: :recur_len, message: nil, mod: Test, pid: _, return_value: 5, type: :exit}
    assert_receive %CallSeq.Event{arity: 2, depth: 0, fun: :recur_len, message: nil, mod: Test, pid: _, return_value: 5, type: :exit}

    assert_receive {:done_tracing, :stop_command}
    # not expeting more events
    refute_receive(_)
  end

  test "CallSeq with start_mach fun, ignore_recursion" do
    test_pid = self()

    res = start_tool(CallSeq,
                     process: test_pid,
                     ignore_recursion: true,
                     forward_to: test_pid,
                     start_match: &Test.recur_len/2)
                    # start_match: Test)
    assert res == :ok

    :timer.sleep(10)

    assert_receive :started_tracing

    recur_len([1, 2, 3, 4, 5], 0)

    :timer.sleep(10)
    res = stop_tool()
    assert res == :ok

    assert_receive %CallSeq.Event{arity: 2, depth: 0, fun: :recur_len, message: nil, mod: Test, pid: _, return_value: nil, type: :enter}
    assert_receive %CallSeq.Event{arity: 2, depth: 0, fun: :recur_len, message: nil, mod: Test, pid: _, return_value: nil, type: :exit}

    assert_receive {:done_tracing, :stop_command}
    # not expeting more events
    refute_receive(_)
  end

end
