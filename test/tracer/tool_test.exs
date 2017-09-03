defmodule Tracer.Tool.Test do
  use ExUnit.Case
  alias Tracer.{Tool, Probe}

  defmodule TestTool do
    use Tool
    alias Tracer.Tool.Test.TestTool

    defstruct dummy: []

    def init(opts) do
      init_tool(%TestTool{}, opts)
    end

    def handle_event(event, state) do
      report_event(state, {:event, event})
      state
    end

    def handle_start(state) do
      report_event(state, :start)
      state
    end

    def handle_flush(state) do
      report_event(state, :flush)
      state
    end

    def handle_stop(state) do
      report_event(state, :stop)
      state
    end

    def handle_valid?(state) do
      report_event(state, :valid?)
      {:error, :foo}
    end

    def trigger_report_event(state, message) do
      report_event(state, message)
    end

    def call_get_process(state) do
      get_process(state)
    end
  end

  test "init() initializes tool" do
    tool = TestTool.init([])

    assert Map.get(tool, :"__tool__") == %Tool{process: self()}
  end

  test "init() raises error if opts is not a list" do
    assert_raise ArgumentError,
                 "arguments needs to be a map and a keyword list",
                 fn ->
                   TestTool.init(:foo)
                 end
  end

  test "init() properly stores options" do
    tool = TestTool.init(process: :c.pid(0, 42, 0),
                          forward_to: :c.pid(0, 43, 0),
                          max_message_count: 777,
                          max_queue_size: 2000,
                          max_tracing_time: 10_000,
                          nodes: [:"local@127,0.0,1", :"remote@127.0.0.1"],
                          probes: [Probe.new(type: :call, process: self())],
                          probe: Probe.new(type: :procs, process: self()),
                          other_keys: "foo"
                          )

    assert Map.get(tool, :"__tool__") == %Tool{
      process: :c.pid(0, 42, 0),
      forward_to: :c.pid(0, 43, 0),
      agent_opts: [
        max_message_count: 777,
        max_queue_size: 2000,
        max_tracing_time: 10_000,
        nodes: [:"local@127,0.0,1", :"remote@127.0.0.1"],
      ],
      probes: [Probe.new(type: :call, process: self()),
               Probe.new(type: :procs, process: self())]
    }
  end

  test "add_probe() adds a probe to the tool" do
    tool = TestTool.init([])
    |> Tool.add_probe(Probe.new(type: :call, process: self()))

    assert Map.get(tool, :"__tool__") == %Tool{
      process: self(),
      probes: [Probe.new(type: :call, process: self())]
    }
  end

  test "remove_probe() removes probe from the tool" do
    tool = TestTool.init([])
    |> Tool.add_probe(Probe.new(type: :call, process: self()))
    |> Tool.remove_probe(Probe.new(type: :call, process: self()))

    assert Map.get(tool, :"__tool__") == %Tool{
      process: self(),
      probes: []
    }
  end

  test "get_probes() retrieves the tool probes" do
    tool = TestTool.init([])
    |> Tool.add_probe(Probe.new(type: :call, process: self()))

    res = Tool.get_probes(tool)
    assert res == [Probe.new(type: :call, process: self())]
  end

  test "report_event() sends event to forward_to process" do
    tool = TestTool.init([forward_to: self()])

    TestTool.trigger_report_event(tool, :foo)

    assert_receive :foo
    refute_receive _
  end

  test "get_process() retrieves configured process" do
    tool = TestTool.init([process: :c.pid(0, 42, 0)])

    assert TestTool.call_get_process(tool) == :c.pid(0, 42, 0)
  end

  test "handle_xxx() calls are routed to tool" do
    tool = TestTool.init([forward_to: self()])

    TestTool.handle_valid?(tool)
    assert_receive :valid?

    TestTool.handle_start(tool)
    assert_receive :start

    TestTool.handle_event(:foo, tool)
    assert_receive {:event, :foo}

    TestTool.handle_flush(tool)
    assert_receive :flush

    TestTool.handle_stop(tool)
    assert_receive :stop

    refute_receive _
  end

  test "valid?() fails if no probes are configured" do
    tool = TestTool.init([])

    assert_raise ArgumentError,
                 "missing probes, maybe a missing match option?",
                 fn -> Tool.valid?(tool) end
  end

  test "valid?() invokes handle_valid?() for tool to validate its own settings" do
    tool = TestTool.init(forward_to: self(),
                         probes: [Probe.new(type: :call, process: self())])

    assert Tool.valid?(tool) == {:error, :foo}
    assert_receive :valid?
    refute_receive _
  end
end
