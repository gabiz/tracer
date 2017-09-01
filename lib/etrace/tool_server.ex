defmodule ETrace.ToolServer do
  @moduledoc """
  The ToolServer module has a process that receives the events from the
  pid_handler and reports the events.
  """

  alias __MODULE__
  alias ETrace.{Event, EventCall, EventReturnTo, EventReturnFrom,
                Tool}

  defstruct tool_type: nil,
            tool_state: nil

  def start(%{"__tool__": _} = tool) do
    initial_state = %ToolServer{}
    |> Map.put(:tool_state, Tool.handle_start(tool))

    spawn_link(fn -> process_loop(initial_state) end)
  end

  def stop(nil), do: :ok
  def stop(pid) when is_pid(pid) do
      send pid, :stop
  end

  def flush(nil), do: :ok
  def flush(pid) when is_pid(pid) do
      send pid, :flush
  end

  defp process_loop(%ToolServer{} = state) do
    receive do
      :stop ->
        state
        |> Map.put(:tool_state, Tool.handle_stop(state.tool_state))
        exit(:done_reporting)
      :flush ->
        state
        |> Map.put(:tool_state, Tool.handle_flush(state.tool_state))
        |> process_loop()
      trace_event when is_tuple(trace_event) ->
        state
        |> handle_trace_event(trace_event)
        |> process_loop()
      _ignored -> process_loop(state)
    end
  end

  defp handle_trace_event(state, trace_event) do
    trace_event = case trace_event do
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

    put_in(state.tool_state, Tool.handle_event(trace_event, state.tool_state))
  end

  defp now do
    :erlang.timestamp()
  end

end
