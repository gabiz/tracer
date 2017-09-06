defmodule Tracer.Tool.Duration do
  @moduledoc """
  Reports duration type traces
  """
  alias __MODULE__
  alias Tracer.{EventCall, EventReturnFrom, Matcher, Probe,
                Tool.Duration.Event, Collect, ProcessHelper}

  use Tracer.Tool

  defstruct durations: %{},
            aggregation: nil,
            stacks: %{},
            collect: nil

  def init(opts) when is_list(opts) do
    init_state = %Duration{}
    |> init_tool(opts, [:match, :aggregation])
    |> Map.put(:aggregation,
                aggreg_fun(Keyword.get(opts, :aggregation, nil)))
    |> Map.put(:collect, Collect.new())

    case Keyword.get(opts, :match) do
      nil -> init_state
      %Matcher{} = matcher ->
        ms_with_return_trace = matcher.ms
        |> Enum.map(fn {head, condit, body} ->
          {head, condit, [{:return_trace} | body]}
        end)
        matcher = put_in(matcher.ms, ms_with_return_trace)

        node = Keyword.get(opts, :node)
        process = init_state
        |> get_process()
        |> ProcessHelper.ensure_pid(node)

        all_child = ProcessHelper.find_all_children(process, node)
        probe_call = Probe.new(type: :call,
                               process: [process | all_child],
                               match: matcher)
        probe_spawn = Probe.new(type: :set_on_spawn,
                                process: [process | all_child])

        set_probes(init_state, [probe_call, probe_spawn])
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

            event = %Event{
                duration: duration,
                pid: pid,
                mod: mod,
                fun: fun,
                arity: arity,
                message: c
            }

            state
            |> handle_aggregation_if_needed(event)
            |> Map.put(:stacks, Map.put(state.stacks, key, poped_stack))
          _ ->
            report_event(state, "entry point not found for" <>
                              " #{inspect mod}.#{fun}/#{arity}")
          state
        end
      _ -> state
    end
  end

  def handle_stop(%Duration{aggregation: nil} = state), do: state
  def handle_stop(state) do
    state.collect
    |> Collect.get_collections()
    |> Enum.each(fn {{mod, fun, arity, message}, value} ->
      event = %Event{
          duration: state.aggregation.(value),
          mod: mod,
          fun: fun,
          arity: arity,
          message: message
      }

      report_event(state, event)
    end)
    state
  end

  defp handle_aggregation_if_needed(%Duration{aggregation: nil} = state,
                                    event) do
    report_event(state, event)
    state
  end
  defp handle_aggregation_if_needed(state,
    %Event{mod: mod, fun: fun, arity: arity,
           message: message, duration: duration}) do
    collect = Collect.add_sample(
      state.collect,
      {mod, fun, arity, message},
      duration)
    put_in(state.collect, collect)
  end

  defp ts_to_ms({mega, seconds, us}) do
    (mega * 1_000_000 + seconds) * 1_000_000 + us # round(us/1000)
  end

  defp aggreg_fun(:nil), do: nil
  defp aggreg_fun(:max), do: &Enum.max/1
  defp aggreg_fun(:mix), do: &Enum.min/1
  defp aggreg_fun(:sum), do: &Enum.sum/1
  defp aggreg_fun(:avg), do: fn list -> Enum.sum(list) / length(list) end
  defp aggreg_fun(:dist), do: fn list ->
    Enum.reduce(list, %{}, fn val, buckets ->
      index = log_bucket(val)
      Map.put(buckets, index, Map.get(buckets, index, 0) + 1)
    end)
  end
  defp aggreg_fun(other) do
    raise ArgumentError, message: "unsupported aggregation #{inspect other}"
  end

  defp log_bucket(x) do
    # + 0.01 avoid 0 to trap
    round(:math.pow(2, Float.floor(:math.log(x + 0.01) / :math.log(2))))
  end
end
