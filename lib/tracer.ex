defmodule Tracer do
  @moduledoc """
  **Tracer** is a tracing framework for elixir which features an easy to use high level interface, extensibility and safety for using in production.

  To run a tool use the `run` command. Tracing only happens when the tool is running.
  All tools accept the following parameters:
    * `node: node_name` - Option to run the tool remotely.
    * `max_tracing_time: time` - Maximum time to run tool (30sec).
    * `max_message_count: count` - Maximum number of events (1000)
    * `max_queue_size: size` - Maximum message queue size (1000)
    * `process: pid` - Process to trace, also accepts regigered names,
                       and :all, :existing, :new
    * `forward_pid: pid` - Forward results as messages insted of printing
                           to the display.
  ## Examples
    ```
    iex> run Count, process: self(), match: global String.split(string, pattern)
    :ok

    iex> String.split("Hello World", " ")
    ["Hello", "World"]

    iex> String.split("Hello World", " ")
    ["Hello", "World"]

    iex String.split("Hello World", "o")
    ["Hell", " W", "rld"]

    iex> String.split("Hello", "o")
    ["Hell", ""]

    iex> stop
    :ok

            1              [string:"Hello World", pattern:"o"]
            1              [string:"Hello"      , pattern:"o" ]
            2              [string:"Hello World", pattern:" "]
  ```
  """
  alias Tracer.{Server, Probe, Tool}
  import Tracer.Macros
  defmacro __using__(_opts) do
    quote do
      import Tracer
      import Tracer.Matcher
      alias Tracer.{Tool, Probe, Clause}
      alias Tracer.Tool.{Display, Count, CallSeq, Duration, FlameGraph}
      :ok
    end
  end

  delegate :start_server, to: Server, as: :start
  delegate :stop_server, to: Server, as: :stop
  delegate :stop, to: Server, as: :stop_tool
  delegate_1 :set_tool, to: Server, as: :set_tool

  def probe(params) do
    Probe.new(params)
  end

  def probe(type, params) do
    Probe.new([type: type] ++ params)
  end

  def tool(type, params) do
    Tool.new(type, params)
  end

  @doc """
  Runs a tool. Tracing only happens when the tool is running.
    * `tool_name` - The name of the tool that want to run.
    * `node: node_name` - Option to run the tool remotely.
    * `max_tracing_time: time` - Maximum time to run tool (30sec).
    * `max_message_count: count` - Maximum number of events (1000)
    * `max_queue_size: size` - Maximum message queue size (1000)
    * `process: pid` - Process to trace, also accepts regigered names,
                       and :all, :existing, :new
    * `forward_pid: pid` - Forward results as messages insted of printing
                           to the display.
  ## Examples
    ```
    iex> run Count, process: self(), match: global String.split(string, pattern)
    :ok

    iex> String.split("Hello World", " ")
    ["Hello", "World"]

    iex> String.split("Hello World", " ")
    ["Hello", "World"]

    iex> String.split("Hello World", "o")
    ["Hell", " W", "rld"]

    iex> String.split("Hello", "o")
    ["Hell", ""]

    iex> stop
    :ok

            1              [string:"Hello World", pattern:"o"]
            1              [string:"Hello"      , pattern:"o" ]
            2              [string:"Hello World", pattern:" "]
    ```
  """
  def run(%{"__tool__": _} = tool) do
    Server.start_tool(tool)
  end
  def run(tool_name, params) do
    Server.start_tool(tool(tool_name, params))
  end

end
