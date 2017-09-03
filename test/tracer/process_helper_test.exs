defmodule Tracer.ProcessHelper.Test do
  use ExUnit.Case
  alias Tracer.ProcessHelper

  test "ensure_pid() returns pid for a pid" do
    assert ProcessHelper.ensure_pid(self()) == self()
  end

  test "ensure_pid() traps when for a non registered name" do
    assert_raise ArgumentError, "Foo is not a registered process", fn ->
      ProcessHelper.ensure_pid(Foo)
    end
  end

  test "ensure_pid() returns the pid from a registered process" do
    Process.register(self(), Foo)
    assert ProcessHelper.ensure_pid(Foo) == self()
  end

  test "type() handles regular processes" do
    res = ProcessHelper.type(self())
    assert res == :regular
  end

  test "type() handles supervisor processes" do
    res = ProcessHelper.type(:kernel_sup)
    assert res == :supervisor
  end

  test "type() handles worker processes" do
    res = ProcessHelper.type(:file_server_2)
    assert res == :worker
  end

  test "find_children() for supervisor processes" do
    res = ProcessHelper.find_children(Logger.Supervisor)
    assert length(res) == 4
  end

  test "find_all_children() for workers processes" do
    assert ProcessHelper.find_all_children(self()) == []
  end

  test "find_all_children() for supervisor processes" do
    res = ProcessHelper.find_all_children(Logger.Supervisor)
    assert length(res) == 5
  end

end
