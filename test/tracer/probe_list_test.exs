defmodule Tracer.ProbeList.Test do
  use ExUnit.Case

  alias Tracer.{ProbeList, Probe}

  # test "new returns a tracer" do
  #   assert Tracer.new() == %Tracer{}
  # end
  #
  # test "new accepts a probe shorthand" do
  #   res = Tracer.new(probe: Probe.new(type: :call))
  #     |> Tracer.probes()
  #
  #   assert res == [Probe.new(type: :call)]
  # end

  test "add_probe complains if not passed a probe" do
    res = ProbeList.add_probe([], %{})
    assert res == {:error, :not_a_probe}
  end

  test "add_probe adds probe to probe list" do
    res = ProbeList.add_probe([], Probe.new(type: :call))
    assert res == [Probe.new(type: :call)]
  end

  test "add_probe fails if probe_list has a probe of the same type" do
    res = []
      |> ProbeList.add_probe(Probe.new(type: :call))
      |> ProbeList.add_probe(Probe.new(type: :call))

    assert res == {:error, :duplicate_probe_type}
  end

  test "remove_probe removes probe from probe list" do
    res = []
      |> ProbeList.add_probe(Probe.new(type: :call))
      |> ProbeList.remove_probe(Probe.new(type: :call))

    assert res == []
  end

  test "valid? returns error if not probes have been configured" do
    res = ProbeList.valid?([])

    assert res == {:error, :missing_probes}
  end

  test "valid? return error if probes are invalid" do
    res = []
      |> ProbeList.add_probe(Probe.new(type: :call))
      |> ProbeList.add_probe(Probe.new(type: :send))
      |> ProbeList.valid?()

    assert res == {:error, {:invalid_probe, [
      {:error, :missing_processes, Probe.new(type: :send)},
      {:error, :missing_processes, Probe.new(type: :call)}
      ]}}
  end

end
