defmodule Tracer.Tool.FlameGraph do
  @moduledoc """
  This tool generates a flame graph
  """
  alias __MODULE__
  alias Tracer.{Probe, ProcessHelper,
                EventCall, EventReturnTo, EventIn, EventOut}
  use Tracer.Tool
  import Tracer.Matcher

  @root_dir File.cwd!
  @flame_graph_script Path.join(~w(#{@root_dir} scripts gen_flame_graph.sh))

  defstruct file_name: nil,
            ignore: nil,
            resolution: nil,
            max_depth: nil,
            process_state: %{}

  def init(opts) when is_list(opts) do
    init_state = %FlameGraph{}
    |> init_tool(opts, [:file_name, :resolution, :max_depth, :ignore])
    |> Map.put(:file_name,
                Keyword.get(opts, :file_name, "flame_graph.svg"))
    |> Map.put(:resolution,
                Keyword.get(opts, :resolution, 1_000))
    |> Map.put(:max_depth,
                Keyword.get(opts, :max_depth, 50))
    |> Map.put(:ignore,
                Keyword.get(opts, :ignore, []))

    node = Keyword.get(opts, :node)
    process = init_state
    |> get_process()
    |> ProcessHelper.ensure_pid(node)

    process = [process | ProcessHelper.find_all_children(process, node)]
    probe_call = Probe.new(type: :call,
                           process: process,
                           match: local _)
    |> Probe.return_to(true)

    probe_spawn = Probe.new(type: :set_on_spawn,
                            process: process)

    probe_sched = Probe.new(type: :sched,
                            process: process)

    set_probes(init_state, [probe_call, probe_spawn, probe_sched])
  end

  def handle_event(event, state) do
    process_state = Map.get(state.process_state,
                            event.pid,
                            %{
      stack: [],
      stack_acc: [],
      last_ts: 0
    })

    put_in(state.process_state,
           Map.put(state.process_state,
                   event.pid,
                   handle_event_for_process(event, process_state)))
  end

  defp handle_event_for_process(event, state) do
    case event do
      %EventCall{} -> handle_event_call(event, state)
      %EventReturnTo{} -> handle_event_return_to(event, state)
      %EventIn{} -> handle_event_in(event, state)
      %EventOut{} -> handle_event_out(event, state)
      _ -> state
    end
  end

  defp handle_event_call(%EventCall{mod: m, fun: f, arity: a, ts: ts},
                         state) do
    ms_ts = ts_to_ms(ts)
    state
    |> report_stack(ms_ts)
    |> push_stack("#{inspect(m)}.#{sanitize_function_name(f)}/#{inspect(a)}")
  end

  defp handle_event_return_to(%EventReturnTo{mod: m, fun: f, arity: a, ts: ts},
                              state) do
    ms_ts = ts_to_ms(ts)
    state
    |> report_stack(ms_ts)
    |> pop_stack_to("#{inspect(m)}.#{sanitize_function_name(f)}/#{inspect(a)}")
  end

  defp handle_event_in(%EventIn{ts: ts},
                       state) do
    ms_ts = ts_to_ms(ts)
    state
    |> report_stack(ms_ts)
    |> pop_sleep()
  end

  defp handle_event_out(%EventOut{ts: ts},
                        state) do
    ms_ts = ts_to_ms(ts)
    state
    |> report_stack(ms_ts)
    |> push_stack("sleep")
  end

  def handle_stop(state) do
    stack_list = Enum.map(state.process_state,
             fn {pid, %{stack_acc: stack_acc}} ->
               stack_acc
               |> filter_max_depth(state.max_depth)
               |> filter_ignored(state.ignore)
               |> format_stacks()
               |> collapse_stacks()
               |> filter_below_resolution(state.resolution)
               |> format_with_pid(pid)
             end)

    {:ok, file} = File.open("/tmp/flame_graph.txt", [:write])
    IO.write file, stack_list
    File.close(file)
    # System.cmd("/Users/gabiz/Desktop/Root/ElixirConf-2017/tracer/scripts/gen_flame_graph.sh", ["/tmp/flame_graph.txt", state.file_name])
    System.cmd(@flame_graph_script, ["/tmp/flame_graph.txt", state.file_name])
    state
  end

  defp filter_ignored(stack_acc, ignored) when is_list(ignored) do
    Enum.filter(stack_acc, fn {stack, _time} ->
      !Enum.any?(stack, &Enum.member?(ignored, &1))
    end)
  end
  defp filter_ignored(stack_acc, ignored), do: filter_ignored(stack_acc, [ignored])

  defp filter_max_depth(stack_acc, max_depth) do
    Enum.filter(stack_acc, fn {stack, _time} ->
      length(stack) < max_depth
    end)
  end

  defp format_stacks(stack_acc) do
    Enum.map(stack_acc, fn {stack, ts} ->
      {(stack |> Enum.reverse() |> Enum.join(";")), ts}
    end)
  end

  defp collapse_stacks(stack_acc) do
    Enum.reduce(stack_acc, %{}, fn {stack, ts}, acc ->
      ts_acc = Map.get(acc, stack, 0)
      Map.put(acc, stack, ts_acc + ts)
    end)
  end

  defp filter_below_resolution(stack_acc, resolution) do
    Enum.filter(stack_acc, fn {_stack, time} ->
      div(time, resolution) != 0
    end)
  end

  defp format_with_pid(stack_acc, pid) do
    Enum.map(stack_acc, fn
      {"", time} -> "#{inspect(pid)} #{time}\n"
      {stack, time} -> "#{inspect(pid)};#{stack} #{time}\n"
    end)
  end

  # collapse recursion
  defp push_stack(%{stack: [top | _stack]} = state, top), do: state
  defp push_stack(%{stack: stack} = state, entry) do
    %{state | stack: [entry | stack]}
  end

  defp pop_stack_to(%{stack: stack} = state, entry) do
  # when entry != ":undefined.:undefined/0" do
    stack
    |> Enum.drop_while(fn stack_frame -> stack_frame != entry end)
    |> case do
      [] -> state
      new_stack ->
         %{state | stack: new_stack}
    end
  end
  # # undefined and only one entry
  # defp pop_stack_to(%{stack: [_entry | stack]} = state, entry) do
  #   IO.puts "warning entry #{entry} did not match anything "
  #    %{state | stack: stack}
  # end
  # defp pop_stack_to(%{stack: []} = state, _entry) do
  #   # IO.puts "warning: poping empty for entry #{entry} stack: "
  #   state
  # end
  # defp pop_stack_to(state, entry) do
  #   IO.puts "warning entry #{entry} did not match anything "
  #   state
  # end

  defp pop_sleep(%{stack: ["sleep" | stack]} = state) do
    %{state | stack: stack}
  end
  defp pop_sleep(state), do: state

  defp report_stack(%{last_ts: 0} = state, ts) do
    %{state | last_ts: ts}
  end
  defp report_stack(%{stack: stack,
                      stack_acc: [{stack, stack_time} | stack_acc],
                      last_ts: last_ts} = state,
                    ts) do
    %{state | stack_acc: [{stack, stack_time + (ts - last_ts)} | stack_acc],
              last_ts: ts}
  end
  defp report_stack(%{stack: stack, stack_acc: stack_acc,
                      last_ts: last_ts} = state,
                    ts) do
    %{state | stack_acc: [{stack, ts - last_ts} | stack_acc], last_ts: ts}
  end

  defp ts_to_ms({mega, seconds, us}) do
    (mega * 1_000_000 + seconds) * 1_000_000 + us
  end

  defp sanitize_function_name(f) do
    to_string(f)
  end

end
