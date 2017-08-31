defmodule EtraceTest do
  use ExUnit.Case
  doctest ETrace

  require ETrace
  import ETrace.Matcher

  setup do
    # kill server if alive? for a fresh test
    case Process.whereis(ETrace.Server) do
      nil -> :ok
      pid ->
        Process.exit(pid, :kill)
        :timer.sleep(10)
    end
    :ok
  end

  test "can add multiple probes" do
    {:ok, pid} = ETrace.start()
    assert Process.alive?(pid)
    test_pid = self()

    ETrace.add_probe(ETrace.probe(type: :call, process: :all,
                                  match_by: local do Map.new() -> :ok end))
    ETrace.add_probe(ETrace.probe(type: :gc, process: self()))
    ETrace.add_probe(ETrace.probe(type: :set_on_link, process: [self()]))
    ETrace.add_probe(ETrace.probe(type: :procs, process: [self()]))
    ETrace.add_probe(ETrace.probe(type: :receive, process: [self()]))
    ETrace.add_probe(ETrace.probe(type: :send, process: [self()]))
    ETrace.add_probe(ETrace.probe(type: :sched, process: [self()]))

    probes = ETrace.get_probes()
    assert probes ==
            [
              %ETrace.Probe{enabled?: true, flags: [:arity, :timestamp],
              process_list: [:all], type: :call,
              clauses: [%ETrace.Clause{matches: 0, type: :call,
                        desc: "local do Map.new() -> :ok end",
                        flags: [:local],
                        match_specs: [{[], [], [:ok]}],
              mfa: {Map, :new, 0}}]},
             %ETrace.Probe{clauses: [], enabled?: true,
              flags: [:timestamp], process_list: [test_pid],
              type: :gc},
             %ETrace.Probe{clauses: [], enabled?: true,
              flags: [:timestamp],
              process_list: [test_pid], type: :set_on_link},
             %ETrace.Probe{clauses: [], enabled?: true,
              flags: [:timestamp],
              process_list: [test_pid], type: :procs},
             %ETrace.Probe{clauses: [], enabled?: true,
              flags: [:timestamp],
              process_list: [test_pid], type: :receive},
             %ETrace.Probe{clauses: [], enabled?: true,
              flags: [:timestamp],
              process_list: [test_pid], type: :send},
             %ETrace.Probe{clauses: [], enabled?: true,
              flags: [:timestamp],
              process_list: [test_pid], type: :sched}
            ]

      ETrace.start_trace(display: [], forward_to: self())

      %{tracing: true} = :sys.get_state(ETrace.Server, 100)

      assert_receive :started_tracing

      res = :erlang.trace_info(test_pid, :flags)
      assert res == {:flags, [:arity, :garbage_collection, :running,
                      :set_on_link, :procs,
                      :call, :receive, :send, :timestamp]}
      res = :erlang.trace_info({Map, :new, 0}, :all)
      assert res == {:all,
                      [traced: :local,
                       match_spec: [{[], [], [:ok]}],
                       meta: false,
                       meta_match_spec: false,
                       call_time: false,
                       call_count: false]}

  end

end
