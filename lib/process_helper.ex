defmodule Tracer.ProcessHelper do
  @moduledoc """
  Implements helper functions to find OTP process hierarchy
  """

  @process_keywords [:all, :processes, :ports, :existing, :existing_processes,
                      :existing_ports, :new, :new_processes]

  # ensure_pid
  @process_keywords |> Enum.each(fn keyword ->
    def ensure_pid(unquote(keyword)), do: unquote(keyword)
  end)
  def ensure_pid(pid) when is_pid(pid), do: pid
  def ensure_pid(name) when is_atom(name) do
    case Process.whereis(name) do
      nil ->
        raise ArgumentError,
              message: "#{inspect name} is not a registered process"
      pid when is_pid(pid) -> pid
    end
  end

  def ensure_pid(pid, nil), do: ensure_pid(pid)
  @process_keywords |> Enum.each(fn keyword ->
    def ensure_pid(unquote(keyword), _node), do: unquote(keyword)
  end)
  def ensure_pid(pid, _node) when is_pid(pid), do: pid
  def ensure_pid(name, node) when is_atom(name) do
    case :rpc.call(node, Process, :whereis, [name]) do
      nil ->
        raise ArgumentError,
              message: "#{inspect name} is not a registered process"
      pid when is_pid(pid) -> pid
    end
  end

  # type
  @process_keywords |> Enum.each(fn keyword ->
    def type(unquote(keyword)), do: :keyword
  end)
  def type(pid) do
    dict = pid
    |> ensure_pid()
    |> Process.info()
    |> Keyword.get(:dictionary)

    case dict do
      [] ->
        :regular
      _ ->
        case Keyword.get(dict, :"$initial_call") do
          {:supervisor, _, _} -> :supervisor
          {_, :init, _} -> :worker
          _ -> :regular
        end
    end
  end

  def type(pid, nil), do: type(pid)
  @process_keywords |> Enum.each(fn keyword ->
    def type(unquote(keyword), _node), do: :keyword
  end)
  def type(pid, node) do
    dict = pid
    |> ensure_pid(node)
    |> process_info_on_node(node)
    |> Keyword.get(:dictionary)

    case dict do
      [] ->
        :regular
      _ ->
        case Keyword.get(dict, :"$initial_call") do
          {:supervisor, _, _} -> :supervisor
          {_, :init, _} -> :worker
          _ -> :regular
        end
    end
  end

  # find_children
  @process_keywords |> Enum.each(fn keyword ->
    def find_children(unquote(keyword)), do: []
  end)
  def find_children(pid) do
    pid = ensure_pid(pid)
    case type(pid) do
      :supervisor ->
        child_spec = Supervisor.which_children(pid)
        Enum.reduce(child_spec, [], fn
          {_mod, pid, _type, _params}, acc when is_pid(pid) -> acc ++ [pid]
          _, acc -> acc
        end)
      _ -> []
    end
  end

  def find_children(pid, nil), do: find_children(pid)
  @process_keywords |> Enum.each(fn keyword ->
    def find_children(unquote(keyword), _node), do: []
  end)
  def find_children(pid, node) do
    pid = ensure_pid(pid, node)
    case type(pid, node) do
      :supervisor ->
        child_spec = which_children_on_node(pid, node)
        Enum.reduce(child_spec, [], fn
          {_mod, pid, _type, _params}, acc when is_pid(pid) -> acc ++ [pid]
          _, acc -> acc
        end)
      _ -> []
    end
  end

  # find_all_children
  @process_keywords |> Enum.each(fn keyword ->
    def find_all_children(unquote(keyword)), do: []
  end)
  def find_all_children(pid) do
    pid = ensure_pid(pid)
    case type(pid) do
      :supervisor ->
        find_all_supervisor_children([pid], [])
      _ -> []
    end
  end

  def find_all_supervisor_children([], acc), do: acc
  def find_all_supervisor_children([sup | sups], pids) do
    {s, p} = sup
    |> Supervisor.which_children()
    |> Enum.reduce({[], []}, fn
      {_mod, pid, :supervisor, _params}, {s, p} when is_pid(pid) ->
        {s ++ [pid], p ++ [pid]}
      {_mod, pid, _type, _params}, {s, p} when is_pid(pid) ->
        {s, p ++ [pid]}
      _, acc -> acc
    end)
    find_all_supervisor_children(sups ++ s, pids ++ p)
  end

  def find_all_children(pid, nil), do: find_all_children(pid)
  @process_keywords |> Enum.each(fn keyword ->
    def find_all_children(unquote(keyword), _node), do: []
  end)
  def find_all_children(pid, node) do
    pid = ensure_pid(pid, node)
    case type(pid, node) do
      :supervisor ->
        find_all_supervisor_children([pid], [], node)
      _ -> []
    end
  end

  def find_all_supervisor_children([], acc, node), do: acc
  def find_all_supervisor_children([sup | sups], pids, node) do
    {s, p} = sup
    |> which_children_on_node(node)
    |> Enum.reduce({[], []}, fn
      {_mod, pid, :supervisor, _params}, {s, p} when is_pid(pid) ->
        {s ++ [pid], p ++ [pid]}
      {_mod, pid, _type, _params}, {s, p} when is_pid(pid) ->
        {s, p ++ [pid]}
      _, acc -> acc
    end)
    find_all_supervisor_children(sups ++ s, pids ++ p, node)
  end

  def process_info_on_node(pid, node) do
    :rpc.call(node, Process, :info, [pid])
  end

  def which_children_on_node(pid, node) do
    :rpc.call(node, Supervisor, :which_children, [pid])
  end
end
