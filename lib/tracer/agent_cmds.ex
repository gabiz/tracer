defmodule Tracer.AgentCmds do
  @moduledoc """
  Tracer manages a tracing session
  """
  alias Tracer.{Probe, ProbeList, HandlerAgent}

  # applies trace directly without handler_agent
  def run(_, flags \\ [])
  def run(probes, flags) when is_list(probes) do
    with :ok <- ProbeList.valid?(probes) do
      Enum.map(probes, fn p -> Probe.apply(p, flags) end)
    end
  end
  def run(_, _), do: {:error, :invalid_argument}

  def stop_run do
    :erlang.trace(:all, false, [:all])
  end

  def start(nodes, probes, flags) do
    tracer_pid = Keyword.get(flags, :forward_pid, self())

    start_cmds = get_start_cmds(probes)
    stop_cmds = get_stop_cmds(probes)

    optional_keys = [:max_tracing_time,
                     :max_message_count,
                     :max_message_queue_size]
    agent_flags = [start_trace_cmds: start_cmds,
                   stop_trace_cmds: stop_cmds,
                   forward_pid: tracer_pid] ++
                   Enum.filter(flags,
                      fn {key, _} -> Enum.member?(optional_keys, key) end)

    case nodes do
      nil ->
        [HandlerAgent.start(agent_flags)]
      nodes when is_list(nodes) ->
        Enum.map(nodes, fn n ->
          HandlerAgent.start([node: n] ++ agent_flags)
        end)
      node ->
        [HandlerAgent.start([node: node] ++ agent_flags)]
    end
  end

  def stop(agent_pids) do
    agent_pids
    |> Enum.each(fn agent_pid ->
      send agent_pid, :stop
    end)
    :ok
  end

  def get_start_cmds(probes, flags \\ []) do
    with :ok <- ProbeList.valid?(probes) do
      Enum.flat_map(probes, &Probe.get_trace_cmds(&1, flags))
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

end
