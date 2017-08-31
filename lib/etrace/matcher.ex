defmodule ETrace.Matcher do
  @moduledoc """
  Matcher translate an elixir expression to a tracing matchspec

  This module is based on ericmj's https://github.com/ericmj/ex2ms
  module for ets matchspecs.
  Head logic has been rewritten to accept function like headers instead of
  tuples.
  Body logic has been adapted to support tracing commands
  """
  alias ETrace.Matcher

  defstruct desc: "",
            mfa: nil,
            ms: [],
            flags: []

  @bool_functions [
  :is_atom, :is_float, :is_integer, :is_list, :is_number, :is_pid, :is_port,
  :is_reference, :is_tuple, :is_binary, :is_function, :is_record, :and, :or,
  :not, :xor]

  @guard_functions @bool_functions ++ [
    :abs, :element, :hd, :length, :node, :round, :size, :tl, :trunc, :+, :-, :*,
    :div, :rem, :band, :bor, :bxor, :bnot, :bsl, :bsr, :>, :>=, :<, :<=, :===,
    :==, :!==, :!=, :self]

  @body_custom_functions [
    :count, :gauge, :histogram]

  @body_trace_functions [
    process_dump: 0, caller: 0, return_trace: 0, excpetion_trace: 0,
    self: 0, node: 0, disable_trace: [2, 3], enable_trace: [2, 3],
    get_tcw: 0, set_tcw: 1, get_seq_token: 0, set_seq_token: 2,
    is_seq_token: 0, trace: 2, silent: 1]

  @elixir_erlang [
    ===: :"=:=", !==: :"=/=", !=: :"/=", <=: :"=<", and: :andalso, or: :orelse]

  Enum.map(@guard_functions, fn(atom) ->
    defp is_guard_function(unquote(atom)), do: true
  end)
  defp is_guard_function(_), do: false

  Enum.map(@body_custom_functions, fn(atom) ->
    defp is_custom_function(unquote(atom)), do: true
  end)
  defp is_custom_function(_), do: false

  Enum.map(@body_trace_functions, fn({atom, arity}) ->
    defp is_trace_function(unquote(atom)), do: true
    if is_list(arity) do
      defp trace_function_arity?(unquote(atom), val) do
        Enum.member?(unquote(arity), val)
      end
    else
      defp trace_function_arity?(unquote(atom), val) do
        unquote(arity) == val
      end
    end
  end)
  defp is_trace_function(_), do: false

  Enum.map(@elixir_erlang, fn({elixir, erlang}) ->
    defp map_elixir_erlang(unquote(elixir)), do: unquote(erlang)
  end)
  defp map_elixir_erlang(atom), do: atom

  def base_match(clauses, outer_vars) do
    clauses
    |> Enum.reduce(%Matcher{}, fn({:->, _, clause}, acc) ->
      {head, conds, body, state} = translate_clause(clause, outer_vars)
      acc = if Map.get(state, :mod) != nil do
        clause_mfa = {state.mod, state.fun, state.arity}
        acc_mfa = Map.get(acc, :mfa)
        if acc_mfa != nil and acc_mfa != clause_mfa do
          raise ArgumentError, message:
            "clause mfa #{inspect acc_mfa}" <>
            " does not match #{inspect clause_mfa}"
        end
        Map.put(acc, :mfa, clause_mfa)
      else acc end
      Map.put(acc, :ms, acc.ms ++ [{head, conds, body}])
    end)
  end

  defmacro match([do: clauses]) do
    outer_vars = __CALLER__.vars
    case base_match(clauses, outer_vars) do
      %{mfa: nil} = m ->
        m
        |> Map.get(:ms)
        |> Macro.escape(unquote: true)
      _ -> raise ArgumentError, message: "explicit function not allowed"
    end
  end
  defmacro match(_) do
    raise ArgumentError, message: "invalid args to matchspec"
  end

  [:global, :local] |> Enum.each(fn (flag) ->
    defmacro unquote(flag)([do: clauses]) do
      outer_vars = __CALLER__.vars
      match_desc = "#{unquote(flag)} do " <>
        String.slice(Macro.to_string(clauses), 1..-2) <> " end"
      clauses
      |> base_match(outer_vars)
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

  defmacrop is_literal(term) do
    quote do
      is_atom(unquote(term)) or
      is_number(unquote(term)) or
      is_binary(unquote(term))
    end
  end

  defp translate_clause([head, body], outer_vars) do
    {head, conds, state} = translate_head(head, outer_vars)

    body = translate_body(body, state)
    {head, conds, body, state}
  end

  defp set_annotation(state) do
    Map.put(state, :annotation, true)
  end

  defp annotating?(state) do
    Map.get(state, :annotation, false)
  end

  defp increase_depth(state) do
    Map.put(state, :depth, get_depth(state) + 1)
  end

  defp get_depth(state) do
    Map.get(state, :depth, 0)
  end

  # Translate Body
  defp translate_body({:__block__, _, exprs}, state) when is_list(exprs) do
    body = Enum.map(exprs, &translate_body_term(&1, state))
    if many_messages?(body) do
      raise ArgumentError, message: "multiple messages or incompatible actions"
    else
      body
    end
  end

  defp translate_body(nil, _), do: []
  defp translate_body(expr, state) do
     [translate_body_term(expr, state)]
  end

  defp many_messages?(body) do
    Enum.reduce(body, 0, fn
      {:message, _}, acc -> acc + 1
      _, acc -> acc
    end) > 1
  end

  defp translate_body_term({var, _, nil}, state) when is_atom(var) do
    if match_var = state.vars[var] do
      if annotating?(state), do: [var, :"#{match_var}"], else: :"#{match_var}"
    else
      raise ArgumentError, message: "variable `#{var}` is unbound in matchspec"
    end
  end

  defp translate_body_term({left, right}, state),
    do: translate_body_term({:{}, [], [left, right]}, state)
  defp translate_body_term({:{}, _, list}, state) when is_list(list) do
    list
    |> Enum.map(&translate_body_term(&1, increase_depth(state)))
    |> List.to_tuple
  end

  defp translate_body_term({:%{}, _, list}, state) do
    list
    |> Enum.reduce({%{}, state}, fn {key, value}, {map, state} ->
      value = translate_body_term(value, increase_depth(state))
      {Map.put(map, key, value), state}
    end)
    |> elem(0)
  end

  defp translate_body_term({:^, _, [var]}, _state) do
    {:unquote, [], [var]}
  end

  defp translate_body_term({fun, _, args}, state)
      when fun === :message or fun === :display and is_list(args) do
    if get_depth(state) == 0 do
      match_args = Enum.map(args,
                            &translate_body_term(&1,
                                                state
                                                |> set_annotation()
                                                |> increase_depth()
                                                ))
      {fun, match_args}
    else
      raise ArgumentError, message: "`#{fun}` cannot be nested"
    end
  end

  defp translate_body_term({fun, _, args}, state)
      when is_atom(fun) and is_list(args) do
    cond do
      is_guard_function(fun) ->
        match_args = Enum.map(args,
                              &translate_body_term(&1, increase_depth(state)))
        match_fun = map_elixir_erlang(fun)
        [match_fun | match_args] |> List.to_tuple
      is_custom_function(fun) ->
        if get_depth(state) == 0 do
          match_args = Enum.map(args,
                                &translate_body_term(&1,
                                                    state
                                                    |> set_annotation()
                                                    |> increase_depth()
                                                    ))
          match_fun = map_elixir_erlang(fun)
          {:message, [[:_cmd, match_fun] | match_args]}
        else
          raise ArgumentError, message: "`#{fun}` cannot be nested"
        end
      is_trace_function(fun) ->
        if trace_function_arity?(fun, length(args)) do
          match_args = Enum.map(args,
                                &translate_body_term(&1, increase_depth(state)))
          match_fun = map_elixir_erlang(fun)
          [match_fun | match_args] |> List.to_tuple
        else
          raise ArgumentError,
                message: "`#{fun}/#{length(args)}` is not recognized"
        end
      true ->
        raise ArgumentError, message: "`#{fun}` is not recognized"
    end
  end

  defp translate_body_term(list, state) when is_list(list) do
    Enum.map(list, &translate_body_term(&1, state))
  end

  defp translate_body_term(literal, _state) when is_literal(literal) do
    literal
  end

  defp translate_body_term(_, _state), do: raise_expression_error()

  # Translate Condition
  defp translate_cond({var, _, nil}, state) when is_atom(var) do
    if match_var = state.vars[var] do
      :"#{match_var}"
    else
      raise ArgumentError, message: "variable `#{var}` is unbound in matchspec"
    end
  end

  defp translate_cond({left, right}, state),
    do: translate_cond({:{}, [], [left, right]}, state)
  defp translate_cond({:{}, _, list}, state) when is_list(list) do
    list
    |> Enum.map(&translate_cond(&1, state))
    |> List.to_tuple
  end

  defp translate_cond({:^, _, [var]}, _state) do
    {:unquote, [], [var]}
  end

  defp translate_cond({fun, _, args}, state)
      when is_atom(fun) and is_list(args) do
    if is_guard_function(fun) do
      match_args = Enum.map(args, &translate_cond(&1, state))
      match_fun = map_elixir_erlang(fun)
      [match_fun | match_args] |> List.to_tuple
    else
      raise ArgumentError, message: "`#{fun}` is not allowed in condition"
    end
  end

  defp translate_cond(list, state) when is_list(list) do
    Enum.map(list, &translate_cond(&1, state))
  end

  defp translate_cond(literal, _state) when is_literal(literal) do
    literal
  end

  defp translate_cond(_, _state), do: raise_expression_error()

  # Translate Head
  defp translate_head([{:when, _, params}], outer_vars)
      when is_list(params) and length(params) > 1 do
    {param, condition} = Enum.split(params, -1)

    initial_state = %{vars: [], count: 0, outer_vars: outer_vars}
    {param, state} = extract_fun(param, initial_state)
    {head, state} = do_translate_param(param, state)

    condition = translate_cond(condition, state)
    {head, condition, state}
  end

  defp translate_head([], outer_vars) do
    {[], [], %{vars: [], count: 0, outer_vars: outer_vars}}
  end
  defp translate_head(param, outer_vars) when is_list(param) do
    initial_state = %{vars: [], count: 0, outer_vars: outer_vars}
    {param, state} = extract_fun(param, initial_state)
    {head, state} = do_translate_param(param, state)

    {head, [], state}
  end

  defp translate_head(_, _), do: raise_parameter_error()

  defp extract_fun(head, state) do
    case head do
      # Case 1: Mod.fun._
      [{{:., _, [{:__aliases__, _, mod}, :_]}, _, []}] ->
        {:_, set_mfa(state, Module.concat(mod), :_, :_)}
      # Case 2: Mod.fun(args)
      [{{:., _, [{:__aliases__, _, mod}, fun]}, _, new_head}]
          when is_list(new_head) ->
        {new_head, set_mfa(state, Module.concat(mod), fun, length(new_head))}
      # Case 3: Mod._._
      [{{:., _, [{{:., _, [{:__aliases__, _, mod}, :_]}, _, []}, :_]},
        _, []}] ->
        {:_, set_mfa(state, Module.concat(mod), :_, :_)}
      # Case 4: Mod.fun._
      [{{:., _, [{{:., _, [{:__aliases__, _, mod}, fun]}, _, []}, :_]},
        _, []}] ->
        {:_, set_mfa(state, Module.concat(mod), fun, :_)}
      # Case 5: _._._
      [{{:., _, [{{:., _, [{:_, _, nil}, :_]}, _, []}, :_]}, _, []}] ->
        {:_, set_mfa(state, :_, :_, :_)}
      # Case 6 _._
      [{{:., _, [{:_, _, nil}, :_]}, _, []}] ->
        {:_, set_mfa(state, :_, :_, :_)}
      # Case 7 :mod._
      [{{:., _, [mod, fun]}, _, []}] when is_atom(mod) and is_atom(fun) ->
        {:_, set_mfa(state, mod, fun, :_)}
      [{{:., _, [{{:., _, [mod, fun]}, _, []}, :_]}, _, []}]
          when is_atom(mod) and is_atom(fun) ->
        {[], set_mfa(state, mod, fun, :_)}
      # Case 8 :mod.fun(args)
      [{{:., _, [mod, fun]}, _, new_head}] when is_atom(mod) and is_atom(fun) ->
        {new_head, set_mfa(state, mod, fun, length(new_head))}
      # Case 9 _
      [{:_, _, nil}] ->
        {:_, set_mfa(state, :_, :_, :_)}
      # Case 10 No function, is (args)
      _ -> {head, state}
    end
  end

  defp set_mfa(state, m, f, a) do
    state
    |> Map.put(:mod, m)
    |> Map.put(:fun, f)
    |> Map.put(:arity, a)
  end

  defp do_translate_param({:_, _, nil}, state) do
    {:_, state}
  end

  defp do_translate_param({var, _, nil}, state) when is_atom(var) do
    if match_var = state.vars[var] do
      {:"#{match_var}", state}
    else
      match_var = "$#{state.count+1}"
      state = state
        |> Map.update!(:vars, &[{var, match_var} | &1])
        |> Map.update!(:count, &(&1 + 1))
      {:"#{match_var}", state}
    end
  end

  defp do_translate_param({left, right}, state) do
    do_translate_param({:{}, [], [left, right]}, state)
  end

  defp do_translate_param({:{}, _, list}, state) when is_list(list) do
    {list, state} = Enum.map_reduce(list, state, &do_translate_param(&1, &2))
    {List.to_tuple(list), state}
  end

  defp do_translate_param({:^, _, [var]}, state) do
    {{:unquote, [], [var]}, state}
  end

  defp do_translate_param(list, state) when is_list(list) do
    Enum.map_reduce(list, state, &do_translate_param(&1, &2))
  end

  defp do_translate_param(literal, state) when is_literal(literal) do
    {literal, state}
  end

  defp do_translate_param({:%{}, _, list}, state) do
    Enum.reduce list, {%{}, state}, fn {key, value}, {map, state} ->
      {key, key_state} = do_translate_param(key, state)
      {value, value_state} = do_translate_param(value, key_state)
      {Map.put(map, key, value), value_state}
    end
  end

  defp do_translate_param(_, _state), do: raise_parameter_error()

  defp raise_expression_error do
    raise ArgumentError, message: "illegal expression in matchspec"
  end

  defp raise_parameter_error do
    raise ArgumentError, message: "invalid parameters"
  end

end
