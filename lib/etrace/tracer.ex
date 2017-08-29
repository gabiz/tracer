defmodule ETrace.Tracer do
  @moduledoc """
  Tracer manages a tracing session
  """
  alias __MODULE__

  alias ETrace.{Tracer, Probe, HandlerAgent}

  defstruct probes: [],
            nodes: [],
            agent_pids: []

  def new do
    %Tracer{}
  end

  def new(probe: probe) do
    %Tracer{probes: [probe]}
  end

  def add_probe(tracer, %Probe{} = probe) do
    with false <- Enum.any?(tracer.probes, fn p -> p.type == probe.type end) do
      put_in(tracer.probes, [probe | tracer.probes])
    else
      _ -> {:error, :duplicate_probe_type}
    end
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

  def clear_probes(tracer) do
    put_in(tracer.probes, [])
  end

  def probes(tracer) do
    tracer.probes
  end

  def valid?(tracer) do
    with :ok <- validate_probes(tracer) do
      :ok
    end
  end

  # applies trace directly without handler_agent
  def run(tracer, flags \\ []) do
    with :ok <- valid?(tracer) do
      Enum.each(tracer.probes, fn p -> Probe.apply(p, flags) end)
      tracer
    end
  end

  def stop_run(tracer) do
    :erlang.trace(:all, false, [:all])
    tracer
  end

  def start(tracer, flags) do
    tracer_pid = Keyword.get(flags, :forward_pid, self())

    start_cmds = get_start_cmds(tracer)
    stop_cmds = get_stop_cmds(tracer)

    optional_keys = [:max_tracing_time,
                     :max_message_count,
                     :max_message_queue_size]
    agent_flags = [start_trace_cmds: start_cmds,
                   stop_trace_cmds: stop_cmds,
                   forward_pid: tracer_pid] ++
                   Enum.filter(flags,
                      fn {key, _} -> Enum.member?(optional_keys, key) end)

    flags
    |> Keyword.get(:nodes)
    |> case do
      nil ->
        agent_pid = HandlerAgent.start(agent_flags)
        Map.put(tracer, :agent_pids, [agent_pid])
      nodes when is_list(nodes) ->
        agent_pids = Enum.map(nodes, fn n ->
          HandlerAgent.start([node: n] ++ agent_flags)
        end)
        tracer
        |> Map.put(:nodes, nodes)
        |> Map.put(:agent_pids, agent_pids)
      node ->
        agent_pid = HandlerAgent.start([node: node] ++ agent_flags)
        tracer
        |> Map.put(:nodes, [node])
        |> Map.put(:agent_pids, [agent_pid])
    end
  end

  def stop(tracer) do
    tracer.agent_pids |> Enum.each(fn agent_pid ->
      send agent_pid, :stop
    end)
    tracer
    |> Map.put(:agent_pids, [])
    |> Map.put(:nodes, [])
  end

  def get_start_cmds(tracer, flags \\ []) do
    with :ok <- valid?(tracer) do
      Enum.flat_map(tracer.probes, &Probe.get_trace_cmds(&1, flags))
    else
      error -> raise RuntimeError, message: "invalid trace #{inspect error}"
    end
  end

  def get_stop_cmds(_tracer) do
    [
      [
        fun: &:erlang.trace/3,
        pid_port_spec: :all,
        how: :false,
        flag_list: [:all]
       ],

       [
         fun: &:erlang.trace_pattern/3,
         mfa: {:'_', :'_', :'_'},
         match_specs: false,
         flag_list: [:local, :call_count, :call_time]
       ],

       [
         fun: &:erlang.trace_pattern/3,
         mfa: {:'_', :'_', :'_'},
         match_specs: false,
         flag_list: [:global]
       ]
    ]
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
