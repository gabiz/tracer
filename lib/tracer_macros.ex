defmodule Tracer.Macros do
  @moduledoc """
  Helper Macros
  """

  defmacro delegate(fun, list) do
    quote do
      def unquote(fun)() do
        apply(Keyword.get(unquote(list), :to), unquote(fun), [])
      end
    end
  end

  defmacro delegate_1(fun, list) do
    quote do
      def unquote(fun)(param) do
        apply(Keyword.get(unquote(list), :to), unquote(fun), [param])
      end
    end
  end

  # Pipe helpers
  defmacro tuple_x_and_fx(x, term) do
    quote do: {unquote(x), unquote(x) |> unquote(term)}
  end

  defmacro assign_to(res, target) do
    quote do: unquote(target) = unquote(res)
  end

  # defmacro create_match_spec()
end
