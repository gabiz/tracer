defmodule Tracer.Tool.Count do
  @moduledoc """
  Reports count type traces
  """
  alias __MODULE__
  alias Tracer.{EventCall, Probe, Tool.Count.Event}
  use Tracer.Tool

  defstruct counts: %{}

  def init(opts) when is_list(opts) do
    init_state = init_tool(%Count{}, opts)

    case Keyword.get(opts, :match) do
      nil -> init_state
      matcher ->
        probe = Probe.new(type: :call,
                          process: get_process(init_state),
                          match_by: matcher)
        set_probes(init_state, [probe])
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
