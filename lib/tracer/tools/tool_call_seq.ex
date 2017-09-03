defmodule Tracer.Tool.CallSeq do
  @moduledoc """
  Reports duration type traces
  """
  alias __MODULE__
  alias Tracer.{EventCall, EventReturnFrom, Probe,
                ToolHelper, Tool.CallSeq.Event, ProcessHelper}

  use Tracer.Tool
  import Tracer.Matcher

  defstruct ignore_recursion: nil,
            start_mfa: nil,
            show_args: nil,
            show_return: nil,
            max_depth:  nil,
            started: %{},
            stacks: %{},
            depth: %{}

  @allowed_opts [:ignore_recursion, :max_depth, :show_args,
                 :show_return, :start_match]

  def init(opts) do
    init_state = %CallSeq{}
    |> init_tool(opts, @allowed_opts)
    |> Map.put(:ignore_recursion,
               Keyword.get(opts, :ignore_recursion, true))
    |> Map.put(:max_depth,
              Keyword.get(opts, :max_depth, 20))
    |> Map.put(:show_args,
              Keyword.get(opts, :show_args, false))
    |> Map.put(:show_return,
              Keyword.get(opts, :show_return, false))

    init_state = case Keyword.get(opts, :start_match) do
      nil ->
        init_state
      fun ->
        case ToolHelper.to_mfa(fun) do
          {_m, _f, _a} = mfa ->
            Map.put(init_state, :start_mfa, mfa)
          _error ->
            raise ArgumentError,
              message: "invalid start_match argument #{inspect fun}"
        end
    end

    match_spec = if init_state.show_args do
      local do _ ->
        return_trace()
        message(:"$_") end
    else
      local do _ -> return_trace() end
    end
    process = init_state
    |> get_process()
    |> ProcessHelper.ensure_pid()

    all_child = ProcessHelper.find_all_children(process)
    probe_call = Probe.new(type: :call,
                           process: [process | all_child],
                           match: match_spec)
    probe_spawn = Probe.new(type: :set_on_spawn,
                            process: [process | all_child])

    set_probes(init_state, [probe_call, probe_spawn])
  end

  def handle_event(event, state) do
    case event do
      %EventCall{} -> handle_event_call(event, state)
      %EventReturnFrom{} -> handle_event_return_from(event, state)
      _ -> state
    end
  end

  def handle_event_call(%EventCall{pid: pid, mod: mod, fun: fun, arity: arity,
      ts: ts, message: m}, state) do
    enter_ts_ms = ts_to_ms(ts)
    key = inspect(pid)

    state = if !Map.get(state.started, key, false) and
          match_start_fun(state.start_mfa, {mod, fun, arity}) do
      put_in(state.started, Map.put(state.started, key, true))
    else
      state
    end

    stack_entry = {:enter, {mod, fun, arity, m}, enter_ts_ms}
    push_to_stack_if_started(key, stack_entry, state)
  end

  defp match_start_fun(nil, _), do: true
  defp match_start_fun({mod, fun, arity}, {mod, fun, arity}), do: true
  defp match_start_fun({mod, fun, :_}, {mod, fun, _}), do: true
  defp match_start_fun({mod, :_, :_}, {mod, _, _}), do: true
  defp match_start_fun({:_, :_, :_}, {_, _, _}), do: true
  defp match_start_fun(_, _), do: false

  def handle_event_return_from(%EventReturnFrom{pid: pid, mod: mod, fun: fun,
      arity: arity, ts: ts, return_value: return_value}, state) do
    exit_ts_ms = ts_to_ms(ts)
    key = inspect(pid)

    val = if state.show_return, do: return_value, else: nil
    stack_entry = {:exit, {mod, fun, arity, val}, exit_ts_ms}
    state = push_to_stack_if_started(key, stack_entry, state)

    if Map.get(state.started, key, false) and
        Map.get(state.depth, key, 0) == 0 do
      put_in(state.started, Map.put(state.started, key, false))
    else
      state
    end

  end

  defp push_to_stack_if_started(key, {dir, {mod, fun, arity, val}, ts}, state) do
    if Map.get(state.started, key, false) do
      if state.ignore_recursion do
        state.stacks
        |> Map.get(key, [])
        |> case do
          [{^dir, {^mod, ^fun, ^arity, _r}, _ts} | _] ->
            state
          _ ->
            push_to_stack(key,
                        {dir, {mod, fun, arity, val}, ts},
                        state)
        end
      else
        push_to_stack(key,
                    {dir, {mod, fun, arity, val}, ts},
                    state)
      end
    else
      state
    end
  end

  defp push_to_stack(key, {:enter, _, _} = stack, state) do
    state = if Map.get(state.depth, key, 0) < state.max_depth do
      new_stack = [stack |
                   Map.get(state.stacks, key, [])]
      put_in(state.stacks, Map.put(state.stacks, key, new_stack))
    else
      state
    end
    increase_depth(state, key)
  end
  defp push_to_stack(key, {:exit, _, _} = stack, state) do
    state = if Map.get(state.depth, key, 0) < state.max_depth + 1 do
      new_stack = [stack |
                   Map.get(state.stacks, key, [])]
      put_in(state.stacks, Map.put(state.stacks, key, new_stack))
    else
      state
    end
    increase_depth(state, key, -1)
  end

  defp increase_depth(state, key, incr \\ 1) do
    put_in(state.depth,
           Map.put(state.depth, key, Map.get(state.depth, key, 0) + incr))
  end

  def handle_stop(state) do
    # get stack for each process
    state.stacks |> Enum.each(fn {pid, stack} ->
      stack
      |> Enum.reverse()
      |> Enum.reduce(0, fn
        {:enter, {mod, fun, arity, m}, _enter_ts_ms}, depth ->
          report_event(state, %Event{
            type: :enter,
            depth: depth,
            pid: pid,
            mod: mod,
            fun: fun,
            arity: arity,
            message: m
          })
          depth + 1
        {:exit, {mod, fun, arity, return_value}, _exit_ts_ms}, depth ->
          report_event(state, %Event{
            type: :exit,
            depth: depth - 1,
            pid: pid,
            mod: mod,
            fun: fun,
            arity: arity,
            return_value: return_value
          })
          depth - 1
      end)
    end)
    state
  end

  defp ts_to_ms({mega, seconds, us}) do
    (mega * 1_000_000 + seconds) * 1_000_000 + us # round(us/1000)
  end

end
