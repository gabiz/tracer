defmodule ETrace do
  @moduledoc """
  ETrace API
  """
  alias ETrace.{Server, Probe, Matcher}

  def start do
    Server.start()
  end

  def stop do
    Server.stop()
  end

  def add_probe(probe) do
    Server.add_probe(probe)
  end

  def remove_probe(probe) do
    Server.remove_probe(probe)
  end

  def clear_probes do
    Server.clear_probes()
  end

  def get_probes do
    Server.get_probes()
  end

  def set_probe(probe) do
    Server.clear_probes()
    Server.add_probe(probe)
  end

  def set_nodes(nodes) do
    Server.set_nodes(nodes)
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

      with :ok <- set_probe(Probe.new(probe_flags)) do
        Server.start_trace(trace_flags)
      end
    else
      Server.start_trace(opts)
    end
  end

  def stop_trace do
    Server.stop_trace()
  end

  def probe(params) do
    Probe.new(params)
  end

  [:global, :local] |> Enum.each(fn (flag) ->
    defmacro unquote(flag)([do: clauses]) do
      outer_vars = __CALLER__.vars
      match_desc = "#{unquote(flag)} do " <>
        String.slice(Macro.to_string(clauses), 1..-2) <> " end"
      clauses
      |> Matcher.base_match(outer_vars)
      |> case do
        %{mfa: nil} = bm -> Map.put(bm, :mfa, {:_, :_, :_})
        bm -> bm
      end
      |> Map.put(:flags, [unquote(flag)])
      |> Map.put(:desc, match_desc)
      |> Macro.escape(unquote: true)
    end
    defmacro unquote(flag)(_) do
      raise ArgumentError, message: "invalid args to matchspec"
    end
  end)

end
