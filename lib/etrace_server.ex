defmodule ETrace.Server do
  @moduledoc """
  Orchestrates the tracing session
  """

  # TODO Support multiple reporters
  use GenServer
  alias __MODULE__
  alias ETrace.{Tracer, Reporter, Probe}

  @server_name __MODULE__
  defstruct tracer: nil,
            reporter_pid: nil,
            tracing: false,
            forward_pid: nil

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
  def init(_params) do
    Process.flag(:trap_exit, true)
    {:ok, %Server{tracer: Tracer.new()}}
  end

  def handle_call({:add_probe, probe}, _from, %Server{} = state) do
    {ret, new_state} = case Tracer.add_probe(state.tracer, probe) do
      %Tracer{} = tracer ->
        {:ok, put_in(state.tracer, tracer)}
      error ->
        {error, state}
    end

    {:reply, ret, new_state}
  end

  def handle_call({:remove_probe, probe}, _from, %Server{} = state) do
    {ret, new_state} = case Tracer.remove_probe(state.tracer, probe) do
      %Tracer{} = tracer ->
        {:ok, put_in(state.tracer, tracer)}
      error ->
        {error, state}
    end

    {:reply, ret, new_state}
  end

  def handle_call(:clear_probes, _from, %Server{} = state) do
    {ret, new_state} = case Tracer.clear_probes(state.tracer) do
      %Tracer{} = tracer ->
        {:ok, put_in(state.tracer, tracer)}
      error ->
        {error, state}
    end

    {:reply, ret, new_state}
  end

  def handle_call(:get_probes, _from, %Server{} = state) do
    probes = Tracer.probes(state.tracer)
    {:reply, probes, state}
  end

  def handle_call({:start_trace, opts}, _from, %Server{} = state) do
    with  state = %Server{} <- stop_if_tracing(state),
          {tracer_flags, reporter_flags} <- split_flags(opts),
          {:ok, forward_pid, rf} <- update_report_fun(reporter_flags),
          :ok <- Tracer.valid?(state.tracer),
          ret when is_pid(ret) <- Reporter.start(rf) do
      state = state
      |> Map.put(:reporter_pid, ret)
      |> Map.put(:forward_pid, forward_pid)

      {ret, new_state} = case Tracer.start(state.tracer,
                                           [forward_pid: state.reporter_pid] ++
                                           tracer_flags) do
        %Tracer{} = tracer ->
          new_state = state
          |> Map.put(:tracer, tracer)
          |> Map.put(:tracing, true)
          report_message(state,
                         :started_tracing,
                         "started tracing")
          {:ok, new_state}
        error ->
          {error, state}
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
    tracer_keys = [:max_tracing_time,
                   :max_message_count,
                   :max_message_queue_size,
                   :nodes]
    tracer_flags = Enum.filter(opts,
                            fn {key, _} -> Enum.member?(tracer_keys, key) end)
    reporter_flags = opts
    |> Keyword.delete(:max_tracing_time)
    |> Keyword.delete(:max_message_count)
    |> Keyword.delete(:max_message_queue_size)
    |> Keyword.delete(:nodes)
    {tracer_flags, reporter_flags}
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
    {ret, state} = case Tracer.stop(state.tracer) do
      %Tracer{} = tracer ->
        new_state = state
        |> Map.put(:tracer, tracer)
        |> Map.put(:tracing, false)
        {:ok, new_state}
      error ->
        {error, state}
    end

    Reporter.stop(state.reporter_pid)
    state = put_in(state.reporter_pid, nil)

    {ret, state}
  end

  defp handle_agent_exit(state, pid) do
    agent_pids = state.tracer.agent_pids -- [pid]
    state = put_in(state.tracer.agent_pids, agent_pids)
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
