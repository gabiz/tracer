defmodule ETrace.HandlerAgent do
@moduledoc """
HandlerAgent takes care of starting and stopping traces in the
NUT (node under test), as well as watching over the event handler
as it processes events.
"""
  alias __MODULE__
  alias ETrace.PidHandler

  @default_max_tracing_time 20000

  defstruct handler_pid: nil,
            timer_ref: nil,
            max_tracing_time: @default_max_tracing_time,
            pid_handler_opts: []

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

    if Keyword.get(opts, :event_callback) != nil do
      put_in(state.pid_handler_opts,
          [{:event_callback, Keyword.get(opts, :event_callback)}
           | state.pid_handler_opts])
    else
      put_in(state.pid_handler_opts,
          [{:event_callback, &handler_callback/1} | state.pid_handler_opts])
    end
  end

  defp spawn_in_target(state) do
    spawn_link(fn -> process_loop(state) end)
  end

  defp process_loop(state) do
    receive do
      :start ->
        Process.flag(:trap_exit, true)
        state
        |> start_handler()
        |> start_tracing()
        |> start_timer()
        |> process_loop()
      {:timeout, _timeref, _} ->
        stop_tracing_and_handler(state)
        exit({:done_tracing, :tracing_timeout})
      :stop ->
        stop_tracing_and_handler(state)
        exit({:done_tracing, :stop_command})
      {:EXIT, _, :normal} -> # we should be dead by the time this is sent
        exit(:normal)
      {:EXIT, _, {:message_queue_size, len}} ->
        stop_tracing(state)
        exit({:done_tracing, :message_queue_size, len})
      {:EXIT, _, :max_message_count} ->
        stop_tracing(state)
        exit({:done_tracing, :max_message_count})
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

  defp start_tracing(state) do
    state
  end

  defp stop_tracing(state) do
    state
  end

  defp handler_callback(_event) do
    :ok
  end

end
