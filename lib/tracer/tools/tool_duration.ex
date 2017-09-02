defmodule Tracer.Tool.Duration do
  @moduledoc """
  Reports duration type traces
  """
  alias __MODULE__
  alias Tracer.{EventCall, EventReturnFrom, Matcher, Probe, Tool.Duration.Event}
  use Tracer.Tool

  defstruct durations: %{},
            stacks: %{}

  def init(opts) when is_list(opts) do
    init_state = init_tool(%Duration{}, opts, [:match])

    case Keyword.get(opts, :match) do
      nil -> init_state
      %Matcher{} = matcher ->
        ms_with_return_trace = matcher.ms
        |> Enum.map(fn {head, condit, body} ->
          {head, condit, [{:return_trace} | body]}
        end)
        matcher = put_in(matcher.ms, ms_with_return_trace)
        probe = Probe.new(type: :call,
                          process: get_process(init_state),
                          match_by: matcher)
        set_probes(init_state, [probe])
    end
  end

  def handle_event(event, state) do
    case event do
      %EventCall{pid: pid, mod: mod, fun: fun, arity: arity,
          ts: ts, message: c} ->
        ts_ms = ts_to_ms(ts)
        key = inspect(pid)
        new_stack = [{mod, fun, arity, ts_ms, c} |
                      Map.get(state.stacks, key, [])]
        put_in(state.stacks, Map.put(state.stacks, key, new_stack))

      %EventReturnFrom{pid: pid, mod: mod, fun: fun, arity: arity, ts: ts} ->
        exit_ts = ts_to_ms(ts)
        key = inspect(pid)
        case Map.get(state.stacks, key, []) do
          [] ->
            report_event(state,
                         "stack empty for #{inspect mod}.#{fun}/#{arity}")
            state
          # ignore recursion calls
          [{^mod, ^fun, ^arity, _, _},
           {^mod, ^fun, ^arity, entry_ts, c} | poped_stack] ->
              put_in(state.stacks, Map.put(state.stacks, key,
                [{mod, fun, arity, entry_ts, c} | poped_stack]))
          [{^mod, ^fun, ^arity, entry_ts, c} | poped_stack] ->
            duration = exit_ts - entry_ts

            report_event(state, %Event{
                duration: duration,
                pid: pid,
                mod: mod,
                fun: fun,
                arity: arity,
                message: c
              })

            put_in(state.stacks, Map.put(state.stacks, key, poped_stack))
          _ ->
            report_event(state, "entry point not found for" <>
                              " #{inspect mod}.#{fun}/#{arity}")
          state
        end
      _ -> state
    end
  end

  defp ts_to_ms({mega, seconds, us}) do
    (mega * 1_000_000 + seconds) * 1_000_000 + us # round(us/1000)
  end

end
