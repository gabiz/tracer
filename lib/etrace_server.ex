defmodule ETrace.Server do
  @moduledoc """
  Orchestrates the tracing session
  """

  use GenServer
  alias __MODULE__
  alias ETrace.{AgentCmds, ToolServer, Probe, ProbeList, Tool}

  @server_name __MODULE__
  defstruct tool_server_pid: nil,
            tracing: false,
            forward_pid: nil,
            probes: [],
            nodes: nil,
            agent_pids: [],
            tool: nil

  defmacro ensure_server_up(do: clauses) do
    quote do
      case Process.whereis(@server_name) do
        nil ->
          start()
          unquote(clauses)
        pid ->
          unquote(clauses)
      end
    end
  end

  def start_link(params) do
    GenServer.start_link(__MODULE__, params, [name: @server_name])
  end

  def start do
    ETrace.Supervisor.start_server()
  end

  def stop do
    case Process.whereis(@server_name) do
      nil -> {:error, :not_running}
      pid ->
        GenServer.call(@server_name, :stop_tool)
        ETrace.Supervisor.stop_server(pid)
    end
  end

  [:stop_tool]
  |> Enum.each(fn cmd ->
    def unquote(cmd)() do
      ensure_server_up do
        GenServer.call(@server_name, unquote(cmd))
      end
    end
  end)

  def set_tool(%{"__tool__": _} = tool) do
    with :ok <- Tool.valid?(tool) do
      ensure_server_up do
        GenServer.call(@server_name, {:set_tool, tool})
      end
    else
      error ->
        raise RuntimeError,
              message: "Invalid tool configuration: #{inspect error}"
    end
  end
  def set_tool(_) do
    raise ArgumentError, message: "Argument is not a tool"
  end

  def start_tool(%{"__tool__": _} = tool) do
    ensure_server_up do
      GenServer.call(@server_name, {:start_tool, tool})
    end
  end

  def init(_params) do
    Process.flag(:trap_exit, true)
    {:ok, %Server{}}
  end

  def handle_call({:set_tool, tool}, _from, %Server{} = state) do
    {:reply, :ok, put_in(state.tool, tool)}
  end

  def handle_call({:start_tool, tool}, _from, %Server{} = state) do
    with  %Server{} = state <- stop_if_tracing(state),
          %Server{} = state <- get_running_config(state, tool),
          :ok <- ProbeList.valid?(state.probes),
          ret when is_pid(ret) <- ToolServer.start(tool) do
      state = state
      |> Map.put(:tool_server_pid, ret)

      agent_opts = Tool.get_agent_opts(tool)
      nodes = Keyword.get(agent_opts, :nodes, state.nodes)
      {ret, new_state} = case AgentCmds.start(nodes,
                                           state.probes,
                                           [forward_pid: state.tool_server_pid]
                                              ++ agent_opts) do
        {:error, error} ->
          {{:error, error}, state}
        agent_pids ->
          new_state = state
          |> Map.put(:agent_pids, agent_pids)
          |> Map.put(:nodes, nodes)
          |> Map.put(:tracing, true)
          # TODO get a notification from agents
          :timer.sleep(5)
          report_message(state,
                         :started_tracing,
                         "started tracing")
          {:ok, new_state}
      end

      {:reply, ret, new_state}
    else
      error ->
        {:reply, error, state}
    end
  end

  def handle_call(:stop_tool, _from, %Server{} = state) do
    {ret, state} = handle_stop_trace(state)
    {:reply, ret, state}
  end

  def handle_info({:EXIT, _pid, :done_reporting},
      %Server{} = state) do
    {:noreply, put_in(state.tool_server_pid, nil)}
  end
  def handle_info({:EXIT, pid, {:done_tracing, exit_status}},
      %Server{} = state) do
    state = handle_agent_exit(state, pid)
    report_message(state,
                   {:done_tracing, exit_status},
                   "done tracing: #{inspect exit_status}")
    {:noreply, state}
  end
  def handle_info({:EXIT, pid, {:done_tracing, key, val}},
      %Server{} = state) do
    state = handle_agent_exit(state, pid)
    report_message(state,
                   {:done_tracing, key, val},
                   "done tracing: #{to_string(key)} #{val}")
    {:noreply, state}
  end
  def handle_info({:EXIT, pid, exit_code},
      %Server{} = state) do
    state = handle_agent_exit(state, pid)
    report_message(state,
                   {:done_tracing, exit_code},
                   "done tracing: #{inspect exit_code}")
    {:noreply, state}
  end

  defp get_running_config(state, tool) do
    tool
    |> Tool.get_probes()
    |> case do
      nil -> state
      probes when is_list(probes) ->
        put_in(state.probes, probes)
      probe ->
        put_in(state.probes, [probe])
    end
    |> Map.put(:forward_pid, Tool.get_forward_to(tool))
  end

  defp report_message(state, event, message) do
    if is_pid(state.forward_pid) do
      send state.forward_pid, event
    else
      IO.puts(message)
    end
  end

  defp handle_stop_trace(state) do
    {ret, state} = case AgentCmds.stop(state.agent_pids) do
      {:error, error} ->
        {{:error, error}, state}
      _ ->
        new_state = state
        |> Map.put(:agent_pids, [])
        |> Map.put(:nodes, nil)
        |> Map.put(:tracing, false)
        {:ok, new_state}
    end

    ToolServer.stop(state.tool_server_pid)
    state = put_in(state.tool_server_pid, nil)

    {ret, state}
  end

  defp handle_agent_exit(state, pid) do
    agent_pids = state.agent_pids -- [pid]
    state = put_in(state.agent_pids, agent_pids)
    if Enum.empty?(agent_pids) do
      {_ret, state} = handle_stop_trace(state)
      state
    else
      state
    end
  end

  defp stop_if_tracing(%Server{tracing: false} = state), do: state
  defp stop_if_tracing(state), do: elem(handle_stop_trace(state), 1)
end
