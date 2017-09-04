defmodule Tracer.Duration.Test do
  use ExUnit.Case

  import Tracer
  import Tracer.Matcher
  alias Tracer.Tool.Duration

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

  test "duration tool without aggregaton" do
    test_pid = self()

    res = run(Duration,
              process: test_pid,
              forward_to: test_pid,
              match: local Map.new(val))
    assert res == :ok

    :timer.sleep(50)

    %{tracing: true} = :sys.get_state(Tracer.Server, 100)

    Map.new(%{})
    Map.new(%{a: :foo})

    assert_receive :started_tracing
    assert_receive(%{pid: ^test_pid, mod: Map, fun: :new,
        arity: 1, duration: _, message: [[:val, %{}]]})
    assert_receive(%{pid: ^test_pid, mod: Map, fun: :new,
        arity: 1, duration: _, message: [[:val, %{a: :foo}]]})

    res = stop()
    assert res == :ok

    assert_receive {:done_tracing, :stop_command}
    # not expeting more events
    refute_receive(_)
  end

  test "duration tool with aggregaton" do
    test_pid = self()

    res = run(Duration,
              process: test_pid,
              aggregation: :dist,
              forward_to: test_pid,
              match: local Map.new(val))
    assert res == :ok
    :timer.sleep(50)

    Map.new(%{})
    Map.new(%{a: :foo})

    assert_receive :started_tracing
    :timer.sleep(50)

    res = stop()
    assert res == :ok

    assert_receive %Duration.Event{arity: 1, duration: %{}, fun: :new, message: [[:val, %{}]], mod: Map, pid: nil}
    assert_receive %Duration.Event{arity: 1, duration: %{}, fun: :new, message: [[:val, %{a: :foo}]], mod: Map, pid: nil}
    assert_receive {:done_tracing, :stop_command}
    # not expeting more events
    refute_receive(_)
  end
end
