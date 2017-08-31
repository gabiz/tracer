defmodule ETrace.HandlerAgent do
@moduledoc """
HandlerAgent takes care of starting and stopping traces in the
NUT (node under test), as well as watching over the event handler
as it processes events.
"""
  alias __MODULE__
  alias ETrace.PidHandler
  import ETrace.Macros

  @default_max_tracing_time 30_000

  defstruct node: nil,
            handler_pid: nil,
            timer_ref: nil,
            max_tracing_time: @default_max_tracing_time,
            pid_handler_opts: [],
            start_trace_cmds: [],
            stop_trace_cmds: []

  def start(opts \\ []) do
    initial_state = process_opts(%HandlerAgent{}, opts)
    pid = spawn_in_target(initial_state)
    send pid, :start
    pid
  end

  def stop(pid) do
    send pid, :stop
  end

  defp process_opts(state, opts) do
    state
    |> Map.put(:node, Keyword.get(opts, :node, nil))
    |> Map.put(:start_trace_cmds, Keyword.get(opts, :start_trace_cmds, []))
    |> Map.put(:stop_trace_cmds, Keyword.get(opts, :stop_trace_cmds, []))
    |> assign_to(state)

    state = if Keyword.get(opts, :max_tracing_time) != nil do
      put_in(state.max_tracing_time, Keyword.get(opts, :max_tracing_time))
    else
      state
    end

    state = if Keyword.get(opts, :max_message_count) != nil do
      put_in(state.pid_handler_opts,
          [{:max_message_count, Keyword.get(opts, :max_message_count)}
           | state.pid_handler_opts])
    else
      state
    end

    state = if Keyword.get(opts, :max_message_queue_size) != nil do
      put_in(state.pid_handler_opts,
          [{:max_message_queue_size, Keyword.get(opts, :max_message_queue_size)}
           | state.pid_handler_opts])
    else
      state
    end

    event_callback =
    if Keyword.get(opts, :forward_pid) != nil do
      {:event_callback, {&__MODULE__.forwarding_handler_callback/2,
                          Keyword.get(opts, :forward_pid)}}
    else
      {:event_callback, &__MODULE__.discard_handler_callback/1}
    end

    if Keyword.get(opts, :event_callback) != nil do
      put_in(state.pid_handler_opts,
          [{:event_callback, Keyword.get(opts, :event_callback)}
           | state.pid_handler_opts])
    else
      put_in(state.pid_handler_opts,
          [event_callback | state.pid_handler_opts])
    end
  end

  defp spawn_in_target(state) do
    if state.node != nil do
      [__MODULE__, ETrace.PidHandler] |> Enum.each(fn mod ->
        ensure_loaded_remote(state.node, mod)
      end)
      Node.spawn_link(state.node, fn -> process_loop(state) end)
    else
      spawn_link(fn -> process_loop(state) end)
    end
  end

  defp process_loop(state) do
    receive do
      :start ->
        Process.flag(:trap_exit, true)
        state
        |> start_handler()
        |> stop_tracing()
        |> start_tracing()
        |> start_timer()
        |> process_loop()
      {:timeout, _timeref, _} ->
        stop_tracing_and_handler(state)
        exit({:done_tracing, :tracing_timeout, state.max_tracing_time})
      :stop ->
        stop_tracing_and_handler(state)
        exit({:done_tracing, :stop_command})
      {:EXIT, _, :normal} -> # we should be dead by the time this is sent
        exit(:normal)
      {:EXIT, _, {:message_queue_size, len}} ->
        stop_tracing(state)
        exit({:done_tracing, :message_queue_size, len})
      {:EXIT, _, {:max_message_count, count}} ->
        stop_tracing(state)
        exit({:done_tracing, :max_message_count, count})
      :restart_timer ->
        state
        |> cancel_timer()
        |> start_timer()
        |> process_loop()
      # testing helpers
      {:get_handler_pid, sender_pid} ->
        send sender_pid, {:handler_pid, state.handler_pid}
        process_loop(state)
      {:get_pid_handler_opts, sender_pid} ->
        send sender_pid, {:pid_handler_opts, state.pid_handler_opts}
        process_loop(state)

      _ignore -> process_loop(state)
    end
  end

  defp start_timer(state) do
    ref = :erlang.start_timer(state.max_tracing_time, self(), [])
    put_in(state.timer_ref, ref)
  end

  defp cancel_timer(state) do
    :erlang.cancel_timer(state.timer_ref, [])
    put_in(state.timer_ref, nil)
  end

  defp stop_tracing_and_handler(state) do
    state
    |> stop_tracing()
    |> stop_handler()
  end

  defp start_handler(state) do
    handler_pid = PidHandler.start(state.pid_handler_opts)
    put_in(state.handler_pid, handler_pid)
  end

  defp stop_handler(state) do
    state
    |> Map.get(:handler_pid)
    |> PidHandler.stop()
    put_in(state.handler_pid, nil)
  end

  def start_tracing(state) do
    # TODO store the number of matches, so that it can be send back to admin
    # process
    trace_fun = &:erlang.trace/3
    state.start_trace_cmds
    |> Enum.each(fn
      [{:fun, ^trace_fun} | args] ->
        bare_args = Enum.map(args, fn
          # inject tracer option
          {:flag_list, flags} -> [{:tracer, state.handler_pid} | flags]
          {_other, arg} -> arg
        end)
        # IO.puts("#{inspect trace_fun} args: #{inspect bare_args}")
        _res = apply(trace_fun, bare_args)
        # IO.puts("#{inspect trace_fun} args: #{inspect bare_args}" <>
        # " = #{inspect res}")

      [{:fun, fun} | args] ->
        bare_args = Enum.map(args, &(elem(&1, 1)))
        _res = apply(fun, bare_args)
        # IO.puts("#{inspect fun} args: #{inspect bare_args} = #{inspect res}")
    end)
    state
  end

  def stop_tracing(state) do
    state.stop_trace_cmds
    |> Enum.each(fn [{:fun, fun} | args] ->
      bare_args = Enum.map(args, &(elem(&1, 1)))
      apply(fun, bare_args)
    end)
    state
  end

  # Handler Callbacks
  def discard_handler_callback(_event) do
    :ok
  end

  def forwarding_handler_callback(event, pid) do
    send pid, event
    {:ok, pid}
  end

  # Remote Loading Helpers
  # credit: based on redbug https://github.com/massemanet/redbug
  defp ensure_loaded_remote(node, mod) do
    case :rpc.call(node, mod, :module_info, [:compile]) do
      {:badrpc, {:EXIT, {:undef, _}}} ->
        # module was not found
        load_remote(node, mod)
        ensure_loaded_remote(node, mod)
        :ok
      {:badrpc , _} -> :ok
      info when is_list(info) ->
        case {get_ts(info), get_ts(mod.module_info(:compile))} do
          {:interpreted, _} -> :ok
          {target, host} when target < host -> # old code on target
            load_remote(node, mod)
            ensure_loaded_remote(node, mod)
          _ -> :ok
        end
    end
  end

  defp load_remote(node, mod) do
    {mod, bin, fun} = :code.get_object_code(mod)
    {:module, _mod} = :rpc.call(node, :code, :load_binary, [mod, fun, bin])
  end

  defp get_ts([]), do: :interpreted
  defp get_ts([{:time, time} | _]), do: time
  defp get_ts([_ | rest]), do: get_ts(rest)

end
