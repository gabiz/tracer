defmodule ETrace.ToolRouter do
  @moduledoc """
  Maps tool_type to tool modules
  """

  alias ETrace.{CountTool, DurationTool,
                DisplayTool, CallSeqTool}

  def router(:count), do: CountTool
  def router(:display), do: DisplayTool
  def router(:duration), do: DurationTool
  def router(:call_seq), do: CallSeqTool
  def router(nil), do: DisplayTool

end
