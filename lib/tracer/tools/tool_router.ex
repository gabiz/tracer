defmodule Tracer.ToolRouter do
  @moduledoc """
  Maps tool_type to tool modules
  """

  alias Tracer.{CountTool, DurationTool,
                DisplayTool, CallSeqTool}

  def route(:count), do: CountTool
  def route(:display), do: DisplayTool
  def route(:duration), do: DurationTool
  def route(:call_seq), do: CallSeqTool
  def route(nil), do: DisplayTool
  def route(mod) when is_atom(mod), do: mod
  def route(_), do: {:error, :unknown_tool}

end
