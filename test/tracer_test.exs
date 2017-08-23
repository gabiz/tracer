defmodule ETrace.Tracer.Test do
  use ExUnit.Case
  alias ETrace.{Tracer, Probe, Probe.Clause}
  import ETrace.Matcher
  require ETrace.Probe.Clause

  test "new returns a tracer" do
    assert Tracer.new() == %Tracer{}
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
    tracer2 = tracer
      |> Tracer.run(%{forward_to: self()})

    assert tracer == tracer2
    send self(), :foo

    assert_receive(:foo)
    assert_receive({:trace_ts, ^my_pid, :send, :foo, ^my_pid, _})
    refute_receive({:trace_ts, ^my_pid, :send, :foo, ^my_pid, _})

    # Stop
    res = Tracer.stop(tracer2)

    assert res == tracer2
    send self(), :foo_one_more_time
    refute_receive({:trace_ts, _, _, _, _, _})

  end

  test "run full call tracing" do
    my_pid = self()

    # tracer = Tracer.new()
    #   |> Tracer.add_probe(
    #         Probe.new(type: :call)
    #         |> Probe.add_process(self())
    #         |> Probe.add_clauses(Clause.new()
    #                         |> Clause.put_mfa(Map, :new, 1)
    #                         |> Clause.add_matcher(
    #                           match do (%{items: [a, b]}) -> message(a, b) end
    #                         )
    #                       )
    #                     )


    clause = Clause.new()
                    |> Clause.put_mfa(Map, :new, 1)
                    |> Clause.filter(by:
                        match do (%{items: [a, b]}) -> message(a, b) end)

    tracer = Tracer.new()
      |> Tracer.add_probe(
            Probe.new(type: :call)
            |> Probe.add_process(self())
            |> Probe.add_clauses(clause))

    # Run
    tracer2 = tracer
      |> Tracer.run(%{forward_to: self()})

    assert tracer == tracer2

    # no match
    Map.new(%{other_key: [1, 2]})
    refute_receive({:trace_ts, ^my_pid, :call,
      {Map, :new, 1}, _, _})

    # valid match - ignore timestamps
    Map.new(%{items: [1, 2]})
    assert_receive({:trace_ts, ^my_pid, :call,
      {Map, :new, 1}, [[:a, 1], [:b, 2]], _})

    res = Tracer.stop(tracer2)

    assert res == tracer2

    # not expeting more events
    Map.new(%{items: [1, 2]})
    refute_receive({:trace_ts, _, _, _, _, _})

  end

end
