defmodule ETrace do
  @moduledoc """
  ETrace API
  """
  alias ETrace.{Server, Probe, ToolRouter}
  import ETrace.Macros
  defmacro __using__(_opts) do
    quote do
      import ETrace
      import ETrace.Matcher
      :ok
    end
  end

  delegate :start, to: Server
  delegate :stop, to: Server
  delegate :clear_probes, to: Server
  delegate :get_probes, to: Server
  delegate :stop_trace, to: Server
  delegate :stop_tool, to: Server

  delegate_1 :add_probe, to: Server
  delegate_1 :remove_probe, to: Server
  delegate_1 :set_probe, to: Server
  delegate_1 :set_nodes, to: Server
  delegate_1 :set_tool, to: Server

  def probe(params) do
    Probe.new(params)
  end

  def probe(type, params) do
    Probe.new([type: type] ++ params)
  end

  def tool(type, params) do
    tool_module = ToolRouter.route(type)
    tool_module.init(params)
  end

  def start_tool(%{"__tool__": _} = tool) do
    Server.start_tool(tool)
  end
  def start_tool(type, params) do
    Server.start_tool(tool(type, params))
  end

  def start_trace(opts \\ [display: []]) do
    probe_keys = [:type,
                  :process,
                  :match_by,
                  :with_fun]

    # check if we have any probe flag
    if Enum.any?(opts, fn {f, _} -> Enum.member?(probe_keys, f) end) do
      probe_flags = Enum.filter(opts,
                                fn {f, _} -> Enum.member?(probe_keys, f) end)
      trace_flags = Enum.filter(opts,
                                fn {f, _} -> !Enum.member?(probe_keys, f) end)

      with :ok <- Server.set_probe(Probe.new(probe_flags)) do
        Server.start_trace(trace_flags)
      end
    else
      Server.start_trace(opts)
    end
  end

end
