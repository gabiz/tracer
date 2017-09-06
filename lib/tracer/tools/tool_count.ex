defmodule Tracer.Tool.Count do
  @moduledoc """
  Reports count type traces
  """
  alias __MODULE__
  alias Tracer.{EventCall, Probe, Tool.Count.Event, ProcessHelper}
  use Tracer.Tool

  defstruct counts: %{}

  def init(opts) when is_list(opts) do
    init_state = init_tool(%Count{}, opts, [:match])

    case Keyword.get(opts, :match) do
      nil -> init_state
      matcher ->
        node = Keyword.get(opts, :nodes)
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
      %EventCall{message: message} ->
        key = message_to_tuple_list(message)
        new_count = Map.get(state.counts, key, 0) + 1
        put_in(state.counts, Map.put(state.counts, key, new_count))
      _ -> state
    end
  end

  def handle_stop(state) do
    counts = state.counts
    |> Map.to_list()
    |> Enum.sort(&(elem(&1, 1) < elem(&2, 1)))

    report_event(state, %Event{
        counts: counts
    })

    state
  end

  defp message_to_tuple_list(term) when is_list(term) do
    term
    |> Enum.map(fn
      [key, val] -> {key, val}
      # [key, val] -> {key, inspect(val)}
      other -> {:_unknown, inspect(other)}
     end)
  end

end
