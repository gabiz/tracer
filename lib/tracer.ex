defmodule Tracer do
  @moduledoc """
  Tracer API
  """
  alias Tracer.{Server, Probe, Tool}
  import Tracer.Macros
  defmacro __using__(_opts) do
    quote do
      import Tracer
      import Tracer.Matcher
      alias Tracer.{Tool, Probe, Clause}
      alias Tracer.Tool.{Display, Count, CallSeq, Duration}
      :ok
    end
  end

  delegate :start_server, to: Server, as: :start
  delegate :stop_server, to: Server, as: :stop
  delegate :stop, to: Server, as: :stop_tool
  delegate_1 :set_tool, to: Server, as: :set_tool

  def probe(params) do
    Probe.new(params)
  end

  def probe(type, params) do
    Probe.new([type: type] ++ params)
  end

  def tool(type, params) do
    Tool.new(type, params)
  end

  def run(%{"__tool__": _} = tool) do
    Server.start_tool(tool)
  end
  def run(type, params) do
    Server.start_tool(tool(type, params))
  end

end
