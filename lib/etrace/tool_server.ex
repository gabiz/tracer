defmodule ETrace.ToolServer do
  @moduledoc """
  The ToolServer module has a process that receives the events from the
  pid_handler and reports the events.
  """

  alias __MODULE__
  alias ETrace.{Event, EventCall, EventReturnTo, EventReturnFrom,
                ToolRouter}

  defstruct tool_type: nil,
            tool_state: nil

  def start([]), do: start(display: [])
  def start([{tool_type, tool_options} | _]) do
    initial_state = %ToolServer{tool_type: tool_type}
    |> tool_init(tool_options)

    spawn_link(fn -> process_loop(initial_state) end)
  end
  def start(%{"__tool__": _} = tool) do
    initial_state = %ToolServer{tool_type: Map.get(tool, :__struct__)}
    |> Map.put(:tool_state, tool)

    spawn_link(fn -> process_loop(initial_state) end)
  end

  def stop(nil), do: :ok
  def stop(pid) when is_pid(pid) do
      send pid, :stop
  end

  defp process_loop(%ToolServer{} = state) do
    receive do
      :stop ->
        state
        |> tool_handle_done()
        exit(:done_reporting)
      trace_event when is_tuple(trace_event) ->
        state
        |> handle_trace_event(trace_event)
        |> process_loop()
      _ignored -> process_loop(state)
    end
  end

  defp handle_trace_event(state, trace_event) do
    trace_event
    |> case do
      {:trace_ts, pid, :call, {m, f, a}, message, ts} ->
        %EventCall{mod: m, fun: f, arity: a, pid: pid, message: message, ts: ts}
      {:trace_ts, pid, :call, {m, f, a}, ts} ->
        %EventCall{mod: m, fun: f, arity: a, pid: pid, ts: ts}
      {:trace_ts, pid, :return_from, {m, f, a}, ret, ts} ->
        %EventReturnFrom{mod: m, fun: f, arity: a, pid: pid,
          return_value: ret, ts: ts}
      {:trace_ts, pid, :return_to, {m, f, a}, ts} ->
        %EventReturnTo{mod: m, fun: f, arity: a, pid: pid, ts: ts}
      {:trace, pid, :call, {m, f, a}, [message]} ->
        %EventCall{mod: m, fun: f, arity: a, pid: pid, message: message,
          ts: now()}
      {:trace, pid, :call, {m, f, a}} ->
        %EventCall{mod: m, fun: f, arity: a, pid: pid, ts: now()}
      {:trace, pid, :return_from, {m, f, a}, ret} ->
        %EventReturnFrom{mod: m, fun: f, arity: a, pid: pid,
          return_value: ret, ts: now()}
      {:trace, pid, :return_to, {m, f, a}} ->
        %EventReturnTo{mod: m, fun: f, arity: a, pid: pid, ts: now()}
      _other ->
        %Event{event: trace_event}
    end
    |> tool_handle_event(state)
  end

  defp tool_init(state, opts) do
    tool = ToolRouter.route(state.tool_type)
    tool_state = tool.init(opts)
    Map.put(state, :tool_state, tool_state)
  end

  defp tool_handle_event(event, state) do
    tool = ToolRouter.route(state.tool_type)
    tool_state = tool.handle_event(event, state.tool_state)
    Map.put(state, :tool_state, tool_state)
  end

  defp tool_handle_done(state) do
    tool = ToolRouter.route(state.tool_type)
    tool_state = tool.handle_done(state.tool_state)
    Map.put(state, :tool_state, tool_state)
  end

  defp now do
    :erlang.timestamp()
  end

end
