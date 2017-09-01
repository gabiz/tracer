defmodule Tracer.ProbeList do
  @moduledoc """
  Helper functions to manage and validate a set of probes
  """

  alias Tracer.Probe

  def add_probe(probes, %Probe{} = probe) do
    with false <- Enum.any?(probes, fn p -> p.type == probe.type end) do
      # keep order
      probes ++ [probe]
    else
      _ -> {:error, :duplicate_probe_type}
    end
  end
  def add_probe(_probes, _) do
    {:error, :not_a_probe}
  end

  def remove_probe(probes, %Probe{} = probe) do
    Enum.filter(probes, fn p -> p != probe end)
  end
  def remove_probe(_probes, _) do
    {:error, :not_a_probe}
  end

  def valid?(probes) do
    with :ok <- validate_probes(probes) do
      :ok
    end
  end

  defp validate_probes(probes) do
    if Enum.empty?(probes) do
      {:error, :missing_probes}
    else
      probes
      |> Enum.reduce([], fn p, acc ->
        case Probe.valid?(p) do
          true -> acc
          {:error, error} -> [{:error, error, p} | acc]
        end
      end)
      |> case do
        [] -> :ok
        errors -> {:error, {:invalid_probe, errors}}
      end
    end
  end

end
