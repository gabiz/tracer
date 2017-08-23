defmodule ETrace.Clause do
  @moduledoc """
  Manages a Probe's clause
  """
  alias __MODULE__
  require ETrace.Matcher

  @valid_flags [:global, :local, :meta, :call_count, :call_time]

  defstruct type: nil,
            mfa: nil,
            match_specs: [],
            flags: [],
            matches: 0

  def new do
    %Clause{}
  end

  def get_type(clause) do
    clause.type
  end

  def set_flags(clause, flags) do
    with :ok <- valid_flags?(flags) do
      put_in(clause.flags, flags)
    end
  end

  def get_flags(clause) do
    clause.flags
  end

  def put_mfa(clause, m \\ :_, f \\ :_, a \\ :_)
  def put_mfa(clause, m, f, a)
      when is_atom(m) and is_atom(f) and (is_atom(a) or is_integer(a)) do
    clause
    |> Map.put(:mfa, {m, f, a})
    |> Map.put(:type, :call)
  end
  def put_mfa(_clause, _, _, _) do
    {:error, :invalid_mfa}
  end

  def put_fun(clause, fun) when is_function(fun) do
    case :erlang.fun_info(fun, :type) do
      {:type, :external} ->
        with {m, f, a} <- to_mfa(fun) do
          put_mfa(clause, m, f, a)
        end
      _ ->
        {:error, "#{inspect(fun)} is not an external fun"}
    end
  end

  def get_mfa(clause) do
    clause.mfa
  end

  def add_matcher(clause, matcher) do
    put_in(clause.match_specs, matcher ++ clause.match_specs)
  end

  def filter(clause, [by: matcher]) do
    put_in(clause.match_specs, matcher ++ clause.match_specs)
  end

  def matches(clause) do
    clause.matches
  end

  def valid?(clause) do
    with :ok <- validate_mfa(clause) do
      :ok
    end
  end

  def apply(clause, not_remove \\ true) do
    with :ok <- valid?(clause) do
      res = :erlang.trace_pattern(clause.mfa,
                                  not_remove && clause.match_specs,
                                  clause.flags)
      if not_remove == false do
        put_in(clause.matches, 0)
      else
        if is_integer(res), do: put_in(clause.matches, res), else: clause
      end
    end
  end

  defp validate_mfa(clause) do
    case clause.mfa do
      nil -> {:error, :missing_mfa}
      {m, f, a}
        when is_atom(m) and is_atom(f) and (is_atom(a) or is_integer(a)) -> :ok
      _ -> {:error, :invalid_mfa}
    end
  end

  def valid_flags?(flags) when is_list(flags) do
    with [] <- Enum.reduce(flags, [], fn f, acc ->
      if valid_flag?(f), do: acc, else: [{:invalid_clause_flag, f} | acc]
    end) do
      :ok
    else
      error_list -> {:error, error_list}
    end
  end
  def valid_flags?(flag) do
    if valid_flag?(flag), do: :ok, else: {:error, :invalid_clause_flag}
  end

  defp valid_flag?(flag) do
    Enum.member?(@valid_flags, flag)
  end

  defp to_mfa(fun) do
    with {:module, m} <- :erlang.fun_info(fun, :module),
         {:name, f} <- :erlang.fun_info(fun, :name),
         {:arity, a} <- :erlang.fun_info(fun, :arity) do
      {m, f, a}
    else
      _ -> {:error, :invalid_mfa}
    end
  end

end
