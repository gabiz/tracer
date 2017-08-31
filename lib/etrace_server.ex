defmodule ETrace.Server do
  @moduledoc """
  Orchestrates the tracing session
  """

  # TODO Support multiple reporters
  use GenServer
  alias __MODULE__
  alias ETrace.{AgentCmds, Reporter, Probe, ProbeList}

  @server_name __MODULE__
  defstruct reporter_pid: nil,
            tracing: false,
            forward_pid: nil,
            probes: [],
            nodes: nil,
            agent_pids: []

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
        GenServer.call(@server_name, :stop_trace)
        ETrace.Supervisor.stop_server(pid)
    end
  end

  def start_trace(opts \\ []) do
    ensure_server_up do
      GenServer.call(@server_name, {:start_trace, opts})
    end
  end

  [:stop_trace, :clear_probes, :get_probes]
  |> Enum.each(fn cmd ->
    def unquote(cmd)() do
      ensure_server_up do
        GenServer.call(@server_name, unquote(cmd))
      end
    end
  end)

  def add_probe(%Probe{} = probe) do
    with true <- Probe.valid?(probe) do
      ensure_server_up do
        GenServer.call(@server_name, {:add_probe, probe})
      end
    end
  end
  def add_probe(_) do
    {:error, :not_a_probe}
  end

  def remove_probe(probe) do
    ensure_server_up do
      GenServer.call(@server_name, {:remove_probe, probe})
    end
  end

  def set_nodes(nil) do
    ensure_server_up do
      GenServer.call(@server_name, {:set_nodes, nil})
    end
  end
  def set_nodes([]), do: set_nodes(nil)
  def set_nodes(nodes) when is_list(nodes) do
    if Enum.any?(nodes, fn n -> !is_atom(n) end) do
        {:error, :not_a_node}
    else
      ensure_server_up do
        GenServer.call(@server_name, {:set_nodes, nodes})
      end
    end
  end
  def set_nodes(node), do: set_nodes([node])

  def init(_params) do
    Process.flag(:trap_exit, true)
    {:ok, %Server{}}
  end

  def handle_call({:add_probe, probe}, _from, %Server{} = state) do
    {ret, new_state} = case ProbeList.add_probe(state.probes, probe) do
      {:error, error} ->
        {{:error, error}, state}
      probe_list when is_list(probe_list) ->
        {:ok, put_in(state.probes, probe_list)}
    end

    {:reply, ret, new_state}
  end

  def handle_call({:remove_probe, probe}, _from, %Server{} = state) do
    {ret, new_state} = case ProbeList.remove_probe(state.probes, probe) do
      {:error, error} ->
        {{:error, error}, state}
      probe_list when is_list(probe_list) ->
        {:ok, put_in(state.probes, probe_list)}
    end

    {:reply, ret, new_state}
  end

  def handle_call(:clear_probes, _from, %Server{} = state) do
    {:reply, :ok, put_in(state.probes, [])}
  end

  def handle_call(:get_probes, _from, %Server{} = state) do
    {:reply, state.probes, state}
  end

  def handle_call({:set_nodes, nodes}, _from, %Server{} = state) do
    {:reply, :ok, put_in(state.nodes, nodes)}
  end

  def handle_call({:start_trace, opts}, _from, %Server{} = state) do
    with  state = %Server{} <- stop_if_tracing(state),
          {agents_flags, reporter_flags} <- split_flags(opts),
          {:ok, forward_pid, rf} <- update_report_fun(reporter_flags),
          :ok <- ProbeList.valid?(state.probes),
          ret when is_pid(ret) <- Reporter.start(rf) do
      state = state
      |> Map.put(:reporter_pid, ret)
      |> Map.put(:forward_pid, forward_pid)

      nodes = Keyword.get(opts, :nodes, state.nodes)
      {ret, new_state} = case AgentCmds.start(nodes,
                                           state.probes,
                                           [forward_pid: state.reporter_pid] ++
                                           agents_flags) do
        {:error, error} ->
          {{:error, error}, state}
        agent_pids ->
          new_state = state
          |> Map.put(:agent_pids, agent_pids)
          |> Map.put(:nodes, nodes)
          |> Map.put(:tracing, true)
          # TODO get a notification from agents in the future
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

  def handle_call(:stop_trace, _from, %Server{} = state) do
    {ret, state} = handle_stop_trace(state)
    {:reply, ret, state}
  end

  def handle_info({:EXIT, _pid, :done_reporting},
      %Server{} = state) do
    {:noreply, put_in(state.reporter_pid, nil)}
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

  defp split_flags(opts) do
    agents_keys = [:max_tracing_time,
                   :max_message_count,
                   :max_message_queue_size,
                   :nodes]
    agents_flags = Enum.filter(opts,
                            fn {key, _} -> Enum.member?(agents_keys, key) end)
    reporter_flags = opts
    |> Keyword.delete(:max_tracing_time)
    |> Keyword.delete(:max_message_count)
    |> Keyword.delete(:max_message_queue_size)
    |> Keyword.delete(:nodes)
    {agents_flags, reporter_flags}
  end

  defp update_report_fun(opts) do
    case Keyword.get(opts, :forward_to) do
      nil -> {:ok, nil, opts}
      pid when is_pid(pid) ->
        new_opts = opts
        |> Keyword.delete(:forward_to)
        |> Enum.map(fn {reporter_type, reporter_options} ->
          {reporter_type,
           [{:report_fun, fn event -> send pid, event end} | reporter_options]}
        end)
        {:ok, pid, new_opts}
      _ ->
        {:error, :invalid_forward_to_argument}
    end
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
        |> Map.put(:nodes, [])
        |> Map.put(:tracing, false)
        {:ok, new_state}
    end

    Reporter.stop(state.reporter_pid)
    state = put_in(state.reporter_pid, nil)

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
