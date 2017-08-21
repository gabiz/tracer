defmodule ETrace.Probe do
  @moduledoc """
  Probe manages a single probe
  """

  alias __MODULE__
  alias ETrace.Probe.Clause

  @valid_types [:call, :process, :gc, :sched, :send, :receive]
  @flag_map %{
    call: :call,
    process: :procs,
    sched: :running,
    send: :send,
    receive: :receive
  }

  defstruct type: nil,
            process_list: [],
            clauses: [],
            enabled?: true

  def new(opts) when is_list(opts) do
    case Keyword.fetch(opts, :type) do
      :error -> {:error, :missing_type}
      {:ok, type} ->
        with {:ok, type} <- valid_type?(type) do
          %Probe{type: type}
        end
    end
  end

  def get_type(probe) do
    probe.type
  end

  def process_list(probe) do
    probe.process_list
  end

  def process_list(probe, procs) do
    put_in(probe.process_list, Enum.uniq(procs))
  end

  def add_process(probe, procs) when is_list(procs) do
    put_in(probe.process_list,
      probe.process_list
        |> Enum.concat(procs)
        |> Enum.uniq
    )
  end
  def add_process(probe, proc) do
    put_in(probe.process_list, Enum.uniq([proc | probe.process_list]))
  end

  def remove_process(probe, procs) when is_list(procs) do
    put_in(probe.process_list, probe.process_list -- procs)
  end
  def remove_process(probe, proc) do
    remove_process(probe, [proc])
  end

  def add_clauses(probe, clauses) when is_list(clauses) do
    # if Enum.any?(clauses, fn
    #   %Clause{type: ^probe.type} -> false
    #   %Clause{} -> false
    #   _ -> true
    #   end) do
    #   {:error, :not_a_clause}
    # else
    #   put_in(probe.clauses, Enum.concat(probe.clauses, clauses))
    # end

    with [] <- valid_clauses?(clauses, Probe.get_type(probe)) do
      put_in(probe.clauses, Enum.concat(probe.clauses, clauses))
    else
      error_list -> {:error, error_list}
    end
  end
  def add_clauses(probe, clause) do
    add_clauses(probe, [clause])
  end

  defp valid_clauses?(clauses, expected_type) do
    Enum.reduce(clauses, [], fn
      %Clause{type: ^expected_type}, acc -> acc
      %Clause{} = c, acc -> [{:invalid_clause_type, c} | acc]
      c, acc -> [{:not_a_clause, c} | acc]
    end)
  end

  def remove_clauses(probe, clauses) when is_list(clauses) do
    put_in(probe.clauses, probe.clauses -- clauses)
  end
  def remove_clauses(probe, clause) do
    remove_clauses(probe, [clause])
  end

  def clauses(probe) do
    probe.clauses
  end

  def enable(probe) do
    put_in(probe.enabled?, true)
  end

  def disable(probe) do
    put_in(probe.enabled?, false)
  end

  def enabled?(probe) do
    probe.enabled?
  end

  def valid?(probe) do
    with :ok <- validate_process_list(probe) do
      true
    end
  end

  def apply(probe, tracer_pid) do
    with true <- valid?(probe) do
      # Apply trace commands
      Enum.each(probe.process_list, fn p ->
        :erlang.trace(p, probe.enabled?, [{:tracer, tracer_pid} | flags(probe)])
      end)
      # Apply trace_pattern commands
      Enum.each(probe.clauses, fn c -> Clause.apply(c, probe.enabled?) end)
      probe
    end
  end

  defp flags(probe) do
    [Map.get(@flag_map, probe.type)]
  end

  defp valid_type?(type) do
    if Enum.member?(@valid_types, type) do
      {:ok, type}
    else
      {:error, :invalid_type}
    end
  end

  defp validate_process_list(probe) do
    if Enum.empty?(probe.process_list) do
      {:error, :missing_processes}
    else
      :ok
    end
  end

end
