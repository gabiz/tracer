defmodule ETrace.DisplayTool do
  @moduledoc """
  Reports display type tracing
  """
  alias __MODULE__

  defstruct report_fun: nil

  def init(opts) do
    %DisplayTool{report_fun: Keyword.get(opts, :report_fun,
                                                    &(IO.puts to_string(&1)))}
  end

  def handle_event(event, state) do
    state.report_fun.(event)
    state
  end

  def handle_done(state) do
    state
  end

end
