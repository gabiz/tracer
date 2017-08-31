defmodule ETrace.PidHandler do
  @moduledoc """
  PidHandler is the process consumer handler of trace events
  It passes them to the event_callback once received
  """
  alias __MODULE__
  import ETrace.Macros

  @default_max_message_count  1000
  @default_max_message_queue_size 1000

  defstruct message_count: 0,
            max_message_count: @default_max_message_count,
            max_message_queue_size: @default_max_message_queue_size,
            event_callback: nil

  def start(opts) when is_list(opts) do
    initial_state = opts
    |> Enum.reduce(%PidHandler{}, fn ({keyword, value}, pid_handler) ->
      Map.put(pid_handler, keyword, value)
    end)
    |> tuple_x_and_fx(Map.get(:event_callback))
    |> case do
      {_state, nil} ->
        raise ArgumentError, message: "missing event_callback configuration"
      {state, {cbk_fun, _cbk_state}} when is_function(cbk_fun) ->
        state
      {state, cbk_fun} when is_function(cbk_fun) ->
        case :erlang.fun_info(cbk_fun, :arity) do
          {_, 1} ->
            # encapsulate into arity 2
            put_in(state.event_callback,
                  {fn(e, []) -> {cbk_fun.(e), []} end, []})
          {_, 2} ->
            put_in(state.event_callback, {cbk_fun, []})
          {_, arity} ->
            raise ArgumentError,
              message: "#invalid arity/#{inspect arity} for: #{inspect cbk_fun}"
        end
      {_state, invalid_callback} ->
        raise ArgumentError,
              message: "#invalid event_callback: #{inspect invalid_callback}"
    end

    spawn_link(fn -> process_loop(initial_state) end)
  end

  def stop(pid) when is_pid(pid) do
      send pid, :stop
  end

  defp process_loop(state) do
    check_message_queue_size(state)
    receive do
      :stop -> exit(:normal)
      trace_event when is_tuple(trace_event) ->
        state
        |> handle_trace_event(trace_event)
        |> process_loop()
      _ignored -> process_loop(state)
    end
  end

  defp handle_trace_event(state, trace_event) do
    case Tuple.to_list(trace_event) do
      [trace | _] when trace === :trace or trace === :trace_ts ->
        state
        |> call_event_callback(trace_event)
        |> check_message_count()
      _unknown -> state  # ignore
    end
  end

  defp call_event_callback(state, trace_event) do
    {cbk_fun, cbk_state} = state.event_callback
    case cbk_fun.(trace_event, cbk_state) do
      {:ok, new_cbk_state} ->
        put_in(state.event_callback, {cbk_fun, new_cbk_state})
      error -> exit(error)
    end
  end

  defp check_message_queue_size(%PidHandler{max_message_queue_size: max}) do
    case :erlang.process_info(self(), :message_queue_len) do
      {:message_queue_len, len} when len > max ->
         exit({:message_queue_size, len})
      _ -> :ok
    end
  end

  defp check_message_count(state) do
    state
    |> Map.put(:message_count, state.message_count + 1)
    |> case do
      %PidHandler{message_count: count, max_message_count: max}
        when count >= max -> exit({:max_message_count, state.max_message_count})
      state -> state
    end
  end

end
