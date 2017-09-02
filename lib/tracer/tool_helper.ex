defmodule Tracer.ToolHelper do
  @moduledoc """
  Helper functions for developing tools
  """

  def to_mfa({m, f, a}) when is_atom(m) and is_atom(f) and
    (is_integer(a) or a == :_) do
    {m, f, a}
  end
  def to_mfa(m) when is_atom(m) do
    {m, :_, :_}
  end
  def to_mfa(fun) when is_function(fun) do
    case :erlang.fun_info(fun, :type) do
      {:type, :external} ->
        with {:module, m} <- :erlang.fun_info(fun, :module),
             {:name, f} <- :erlang.fun_info(fun, :name),
             {:arity, a} <- :erlang.fun_info(fun, :arity) do
          {m, f, a}
        else
          _ -> {:error, :invalid_mfa}
        end
      _ ->
        {:error, :not_an_external_function}
    end
  end
  def to_mfa(_), do: {:error, :invalid_mfa}

end
