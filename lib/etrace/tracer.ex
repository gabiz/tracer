defmodule ETrace.Tracer do
  @moduledoc """
  Tracer manages a tracing session
  """

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
    # TO DO: need to manage all this from a separate process
    Process.flag(:trap_exit, true)

    forward_pid = Keyword.get(flags, :forward_pid, self())

    start_cmds = get_trace_cmds(tracer)
    # stop all tracing
    stop_cmds = [
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

    flags
    |> Keyword.get(:nodes)
    |> case do
      nil ->
        agent_pid = HandlerAgent.start(start_trace_cmds: start_cmds,
                                       stop_trace_cmds: stop_cmds,
                                       forward_pid: forward_pid)
        Map.put(tracer, :agent_pids, [agent_pid])
      nodes when is_list(nodes) ->
        agent_pids = Enum.map(nodes, fn n ->
          HandlerAgent.start(node: n,
                             start_trace_cmds: start_cmds,
                             stop_trace_cmds: stop_cmds,
                             forward_pid: forward_pid)
        end)
        tracer
        |> Map.put(:nodes, nodes)
        |> Map.put(:agent_pids, agent_pids)
      node ->
        agent_pid = HandlerAgent.start(node: node,
                                       start_trace_cmds: start_cmds,
                                       stop_trace_cmds: stop_cmds)
        tracer
        |> Map.put(:nodes, [node])
        |> Map.put(:agent_pids, [agent_pid])
    end
  end

  def stop(tracer) do
    tracer.agent_pids |> Enum.each(fn agent_pid ->
      send agent_pid, :stop
    end)

  end

  def get_trace_cmds(tracer, flags \\ []) do
    with :ok <- valid?(tracer) do
      Enum.flat_map(tracer.probes, &Probe.get_trace_cmds(&1, flags))
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
