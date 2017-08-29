defmodule ETrace.Reporter do
  @moduledoc """
  The Reporter module has a process that receives the events from the
  pid_handler and reports the events.
  """

  alias __MODULE__
  alias ETrace.{Event, EventCall, EventReturnTo, EventReturnFrom,
                ReporterRouter}

  defstruct reporter_type: nil,
            reporter_state: nil

  def start([]), do: start(display: [])
  def start([{reporter_type, reporter_options} | _]) do
    initial_state = %Reporter{reporter_type: reporter_type}
    |> reporter_init(reporter_options)

    spawn_link(fn -> process_loop(initial_state) end)
  end

  def stop(nil), do: :ok
  def stop(pid) when is_pid(pid) do
      send pid, :stop
  end

  defp process_loop(%Reporter{} = state) do
    receive do
      :stop ->
        state
        |> reporter_handle_done()
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
    |> reporter_handle_event(state)
  end

  defp reporter_init(state, opts) do
    reporter = ReporterRouter.router(state.reporter_type)
    reporter_state = reporter.init(opts)
    Map.put(state, :reporter_state, reporter_state)
  end

  defp reporter_handle_event(event, state) do
    reporter = ReporterRouter.router(state.reporter_type)
    reporter_state = reporter.handle_event(event, state.reporter_state)
    Map.put(state, :reporter_state, reporter_state)
  end

  defp reporter_handle_done(state) do
    reporter = ReporterRouter.router(state.reporter_type)
    reporter_state = reporter.handle_done(state.reporter_state)
    Map.put(state, :reporter_state, reporter_state)
  end

  defp now do
    :erlang.timestamp()
  end

end
