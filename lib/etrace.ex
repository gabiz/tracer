defmodule ETrace do
  @moduledoc """
  ETrace API
  """
  alias ETrace.{Server, Probe, Matcher}
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

  delegate_1 :add_probe, to: Server
  delegate_1 :remove_probe, to: Server
  delegate_1 :set_probe, to: Server
  delegate_1 :set_node, to: Server

  def probe(params) do
    Probe.new(params)
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

  # [:global, :local] |> Enum.each(fn (flag) ->
  #   defmacro unquote(flag)([do: clauses]) do
  #     outer_vars = __CALLER__.vars
  #     match_desc = "#{unquote(flag)} do " <>
  #       String.slice(Macro.to_string(clauses), 1..-2) <> " end"
  #     clauses
  #     |> Matcher.base_match(outer_vars)
  #     |> case do
  #       %{mfa: nil} = bm -> Map.put(bm, :mfa, {:_, :_, :_})
  #       bm -> bm
  #     end
  #     |> Map.put(:flags, [unquote(flag)])
  #     |> Map.put(:desc, match_desc)
  #     |> Macro.escape(unquote: true)
  #   end
  #   defmacro unquote(flag)(_) do
  #     raise ArgumentError, message: "invalid args to matchspec"
  #   end
  # end)

end
