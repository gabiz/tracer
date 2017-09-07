# Tracer - Elixir Tracing Framework

[![Build Status](https://api.travis-ci.org/gabiz/tracer.svg)](https://travis-ci.org/gabiz/tracer)

**Tracer** is a tracing framework for elixir which features an easy to use high level interface, extensibility and safety for using in production.

## Installation

If you need to integrate **Tracer** to your project, then you can install it from
 [Hex](https://hex.pm/packages/tracer), by adding `tracer` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [{:tracer, "~> 0.1.0"}]
end
```

To use Tracer from the cli, then download it directly from [GitHub](https://github.com/gabiz/tracer).

When firing `iex` you might want to specify the node name so that you can trace other nodes remotely. Then enter the `use Tracer` command to be able to use its functions as commands without the `Tracer` prefix.

```elixir
$ git clone git@github.com:gabiz/tracer.git
...
$ cd tracer

$ mix deps.get
...
$ iex --name tracer@127.0.0.1 -S mix
Erlang/OTP 19 [erts-8.0] [source] [64-bit] [smp:8:8] [async-threads:10] [hipe] [kernel-poll:false] [dtrace]

Interactive Elixir (1.5.1) - press Ctrl+C to exit (type h() ENTER for help)
iex(tracer@127.0.0.1)1> use Tracer
:ok
iex(tracer@127.0.0.1)2>
nil
iex(tracer@127.0.0.1)3> run Count, node: :"phoenix@127.0.0.1", ...
```

## Tools

Tools are tracing components that focus on a specific tracing aspect. They are implemented as Elixir modules so you can create your own tools.

Tracer currently provides the following tools:
* The `Count` tool counts events.
* The `Duration` tool measures how long it takes to execute a function.
* The `CallSeq` - 'Call Sequence' tool displays function call sequences.
* The `FlameGraph` tool which aggregates stack frames over a flame graph.
* The `Display` tool displays standard tracing events.

## Count Tool Example

```elixir
iex(2)> run Count, process: self(), match: global String.split(string, pattern)
started tracing
:ok
iex(3)>
nil
iex(4)> String.split("Hello World", " ")
["Hello", "World"]
iex(5)> String.split("Hello World", " ")
["Hello", "World"]
iex(6)> String.split("Hello World", "o")
["Hell", " W", "rld"]
iex(7)> String.split("Hello", "o")
["Hell", ""]
iex(8)> done tracing: tracing_timeout 30000
        1              [string:"Hello World", pattern:"o"]
        1              [string:"Hello"      , pattern:"o" ]
        2              [string:"Hello World", pattern:" "]
```

## Duration Tool Example

```elixir
iex(1)> run Duration, match: global Map.new(param)
started tracing
:ok
iex(2)> Map.new(%{a: 1})                          
        4                    '#PID<0.151.0>' Map.new/1 [param: %{a: 1}]
%{a: 1}
iex(3)> Map.new(%{b: 2})                          
        3                    '#PID<0.151.0>' Map.new/1 [param: %{b: 2}]
%{b: 2}
iex(4)> Map.new(%{c: [1, 2,3]})                   
        6                    '#PID<0.151.0>' Map.new/1 [param: %{c: [1, 2, 3]}]
%{c: [1, 2, 3]}
iex(5)> stop
:ok
done tracing: :stop_command
```

## Call Sequence Tool Example

```elixir
iex(1)> run CallSeq, show_args: true, show_return: true, start_match: &Map.drop/2,
                      max_message_count: 10000, max_queue_size: 10000
started tracing
:ok
iex(2)> Map.drop(%{a: 1, b: 2, c: 3}, [:a, :b])
%{c: 3}                                
iex(3)> stop
:ok                 
done tracing: :stop_command

-> Map.drop/2             [[%{a: 1, b: 2, c: 3}, [:a, :b]]]
 -> Enum.to_list/1        [[[:a, :b]]]
 <- Enum.to_list/1        [:a, :b]
 -> Map.drop_list/2       [[[:a, :b], %{a: 1, b: 2, c: 3}]]
  -> :maps.remove/2       [[:a, %{a: 1, b: 2, c: 3}]]
  <- :maps.remove/2       %{b: 2, c: 3}
  -> Map.drop_list/2      [[[:b], %{b: 2, c: 3}]]
   -> :maps.remove/2      [[:b, %{b: 2, c: 3}]]
   <- :maps.remove/2      %{c: 3}
   -> Map.drop_list/2     [[[], %{c: 3}]]
   <- Map.drop_list/2     %{c: 3}
  <- Map.drop/2           %{c: 3}
  -> :erl_eval.ret_expr/3 [[%{c: 3}, [], :none]]
  <- :erl_eval.ret_expr/3 {:value, %{c: 3}, []}
 <- :erl_eval.do_apply/6  {:value, %{c: 3}, []}
<- :erl_eval.expr/5       {:value, %{c: 3}, []}
```

## Flame Graph Tool Example

```elixir
iex(17)> run FlameGraph, node: :"phoenix@127.0.0.1", process: SampleApp.Endpoint,
        max_message_count: 10000, max_queue_size: 10000, file_name: "phoenix.svg",
        ignore: "sleep", resolution: 10, max_depth: 100
started tracing
:ok
iex(18)> stop
:ok
done tracing: :stop_command
```

[Click for interactive SVG Flame Graph](https://s3.amazonaws.com/gapix/flame_graph.svg)

![FlameGraph](https://s3.amazonaws.com/gapix/flame_graph.svg?sanitize=true)
<img src="https://s3.amazonaws.com/gapix/flame_graph.svg?sanitize=true">
