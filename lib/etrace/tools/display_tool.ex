defmodule ETrace.DisplayTool do
  @moduledoc """
  Reports display type tracing
  """
  alias __MODULE__
  alias ETrace.Probe
  use ETrace.Tool

  defstruct type: nil

  def init(opts) do
    init_state = init_tool(%DisplayTool{}, opts)

    case Keyword.get(opts, :match) do
      nil -> init_state
      matcher ->
        type = Keyword.get(opts, :type, :call)
        probe = Probe.new(type: type,
                          process: get_process(init_state),
                          match_by: matcher)
        set_probes(init_state, [probe])
    end
  end

  def handle_event(event, state) do
    report_event(state, event)
    state
  end

  def handle_done(state) do
    state
  end

end
