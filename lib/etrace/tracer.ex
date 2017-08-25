defmodule ETrace.Tracer do
  @moduledoc """
  Tracer manages a tracing session
  """

  alias ETrace.{Tracer, Probe}

  defstruct probes: []

  def new do
    %Tracer{}
  end

  def new(probe: probe) do
    %Tracer{probes: [probe]}
  end

  def add_probe(tracer, %Probe{} = probe) do
    put_in(tracer.probes, [probe | tracer.probes])
  end
  def add_probe(_tracer, _) do
    {:error, :not_a_probe}
  end

  def remove_probe(tracer, %Probe{} = probe) do
    put_in(tracer.probes, Enum.filter(tracer.probes, fn p -> p != probe end))
  end
  def remove_probe(_tracer, _) do
    {:error, :not_a_probe}
  end

  def probes(tracer) do
    tracer.probes
  end

  def valid?(tracer) do
    with :ok <- validate_probes(tracer) do
      :ok
    end
  end

  def run(tracer, flags \\ []) do
    with :ok <- valid?(tracer) do
      Enum.each(tracer.probes, fn p -> Probe.apply(p, flags) end)
      tracer
    end
  end

  def stop(tracer) do
    :erlang.trace(:all, false, [:all])
    tracer
  end

  def get_trace_cmds(tracer, flags \\ []) do
    with :ok <- valid?(tracer) do
      Enum.reduce(tracer.probes, [], fn p, acc ->
        acc ++ Probe.get_trace_cmds(p, flags)
      end)
    else
      error -> raise RuntimeError, message: "invalid trace #{inspect error}"
    end
  end

  defp validate_probes(tracer) do
    if Enum.empty?(tracer.probes) do
      {:error, :missing_probes}
    else
      tracer.probes
      |> Enum.reduce([], fn p, acc ->
        case Probe.valid?(p) do
          true -> acc
          {:error, error} -> [{:error, error, p} | acc]
        end
      end)
      |> case do
        [] -> :ok
        errors -> {:error, :invalid_probe, errors}
      end
    end
  end

end
