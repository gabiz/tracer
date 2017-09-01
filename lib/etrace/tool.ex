defmodule ETrace.Tool do
  @moduledoc """
  Module that is used by all Tool implementations
  """
  alias ETrace.{Probe, ProbeList, ToolRouter}

  defmacro __using__(_opts) do
    quote do
      alias ETrace.Tool

      def init_tool(state, opts) do
        tool_state = %Tool{
          forward_to: Keyword.get(opts, :forward_to),
          process: Keyword.get(opts, :process, self()),
          nodes: Keyword.get(opts, :nodes, nil),
          agent_opts: extract_agent_opts(opts)
        }

        state = Map.put(state, :"__tool__", tool_state)

        # all all probe in opts
        Enum.reduce(opts, state, fn
          {:probe, probe}, state ->
            Tool.add_probe(state, probe)
          _, state -> state
        end)
      end

      defp extract_agent_opts(opts) do
        agents_keys = [:max_tracing_time,
                       :max_message_count,
                       :max_message_queue_size,
                       :nodes]
       Enum.filter(opts,
                   fn {key, _} -> Enum.member?(agents_keys, key) end)
       end

      defp set_probes(state, probes) do
        tool_state = state
        |> Map.get(:"__tool__")
        |> Map.put(:probes, probes)
        Map.put(state, :"__tool__", tool_state)
      end

      def get_process(state) do
        Tool.get_tool_field(state, :process)
      end

      defp report_event(state, event) do
        case Tool.get_forward_to(state) do
          nil ->
            IO.puts to_string(event)
          pid when is_pid(pid) ->
            send pid, event
        end
      end

      :ok
    end
  end

  defstruct probes: [],
            forward_to: nil,
            process: [],
            nodes: nil,
            agent_opts: []

  def new(type, params) do
    tool_module = ToolRouter.route(type)
    tool_module.init(params)
  end

  def get_tool_field(state, field) do
    state
    |> Map.get(:"__tool__")
    |> Map.get(field)
  end

  def get_agent_opts(state) do
    get_tool_field(state, :agent_opts)
  end

  def get_nodes(state) do
    get_tool_field(state, :nodes)
  end

  def get_probes(state) do
    get_tool_field(state, :probes)
  end

  def get_forward_to(state) do
    get_tool_field(state, :forward_to)
  end

  def add_probe(state, %ETrace.Probe{} = probe) do
    with true <- Probe.valid?(probe) do
      probes = get_probes(state)
      case ProbeList.add_probe(probes, probe) do
        {:error, error} ->
          {{:error, error}, state}
        probe_list when is_list(probe_list) ->
          tool_state = state
          |> Map.get(:"__tool__")
          |> Map.put(:probes, probe_list)
          Map.put(state, :"__tool__", tool_state)
      end
    end
  end
  def add_probe(_, _) do
    {:error, :not_a_probe}
  end

end
