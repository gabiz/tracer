defmodule ETrace.Tool do
  @moduledoc """
  Module that is used by all Tool implementations
  """
  alias ETrace.{Probe, ProbeList, ToolRouter}

  @callback init([any]) :: any

  defmacro __using__(_opts) do
    quote do
      alias ETrace.Tool
      @behaviour Tool

      def init_tool(%{} = state, opts) when is_list(opts) do
        tool_state = %Tool{
          forward_to: Keyword.get(opts, :forward_to),
          process: Keyword.get(opts, :process, self()),
          agent_opts: extract_agent_opts(opts)
        }

        state = state
        |> Map.put(:"__tool__", tool_state)
        |> set_probes(Keyword.get(opts, :probes, []))

        Enum.reduce(opts, state, fn
          {:probe, probe}, state ->
            Tool.add_probe(state, probe)
          _, state -> state
        end)
      end
      def init_tool(_, _) do
        raise ArgumentError,
              message: "arguments needs to be a map and a keyword list"
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

      defp get_process(state) do
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

      def handle_start(state), do: state
      def handle_event(event, state), do: state
      def handle_flush(state), do: state
      def handle_stop(state), do: state
      def handle_valid?(state), do: :ok

      defoverridable [handle_start: 1,
                      handle_event: 2,
                      handle_flush: 1,
                      handle_stop: 1,
                      handle_valid?: 1]

      :ok
    end
  end

  defstruct probes: [],
            forward_to: nil,
            process: nil,
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

  def set_tool_field(state, field, value) do
    tool_state = state
    |> Map.get(:"__tool__")
    |> Map.put(field, value)
    Map.put(state, :"__tool__", tool_state)
  end

  def get_agent_opts(state) do
    get_tool_field(state, :agent_opts)
  end

  def get_nodes(state) do
    agent_opts = get_tool_field(state, :agent_opts)
    Keyword.get(agent_opts, :nodes, nil)
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
          set_tool_field(state, :probes, probe_list)
      end
    end
  end
  def add_probe(_, _) do
    {:error, :not_a_probe}
  end

  def remove_probe(state, %ETrace.Probe{} = probe) do
    probes = get_probes(state)
    case ProbeList.remove_probe(probes, probe) do
      {:error, error} ->
        {{:error, error}, state}
      probe_list when is_list(probe_list) ->
        set_tool_field(state, :probes, probe_list)
    end
  end

  def valid?(state) do
    with :ok <- ProbeList.valid?(get_probes(state)) do
      handle_valid?(state)
    end
  end

  # Routing Helpers

  def handle_start(%{"__struct__": mod} = state) do
    mod.handle_start(state)
  end

  def handle_event(event, %{"__struct__": mod} = state) do
    mod.handle_event(event, state)
  end

  def handle_flush(%{"__struct__": mod} = state) do
    mod.handle_flush(state)
  end

  def handle_stop(%{"__struct__": mod} = state) do
    mod.handle_stop(state)
  end

  def handle_valid?(%{"__struct__": mod} = state) do
    mod.handle_valid?(state)
  end

end
