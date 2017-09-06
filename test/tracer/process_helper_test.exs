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

  test "ensure_pid() works on other node" do
    :net_kernel.start([:"local2@127.0.0.1"])

    remote_node = "remote#{Enum.random(1..100)}@127.0.0.1"
    remote_node_a = String.to_atom(remote_node)
    spawn(fn ->
        System.cmd("elixir", ["--name", remote_node,
            "-e", "Process.register(self(), Foo); :timer.sleep(1000)"])
    end)

    :timer.sleep(500)
    # check if remote node is up
    case :net_adm.ping(remote_node_a) do
      :pang ->
        assert false
      :pong -> :ok
    end

    pid = ProcessHelper.ensure_pid(Foo, remote_node_a)
    assert is_pid(pid)
    assert node(pid) == remote_node_a
  end

  test "type() works on other node" do
    :net_kernel.start([:"local2@127.0.0.1"])

    remote_node = "remote#{Enum.random(1..100)}@127.0.0.1"
    remote_node_a = String.to_atom(remote_node)
    spawn(fn ->
        System.cmd("elixir", ["--name", remote_node,
            "-e", ":timer.sleep(1000)"])
    end)

    :timer.sleep(500)
    # check if remote node is up
    case :net_adm.ping(remote_node_a) do
      :pang ->
        assert false
      :pong -> :ok
    end

    pid = ProcessHelper.ensure_pid(Logger.Supervisor, remote_node_a)
    assert is_pid(pid)
    assert node(pid) == remote_node_a
    type = ProcessHelper.type(pid, remote_node_a)
    assert type == :supervisor
  end

  test "find_children() for supervisor processes on remote node" do
    :net_kernel.start([:"local2@127.0.0.1"])

    remote_node = "remote#{Enum.random(1..100)}@127.0.0.1"
    remote_node_a = String.to_atom(remote_node)
    spawn(fn ->
        System.cmd("elixir", ["--name", remote_node,
            "-e", ":timer.sleep(1000)"])
    end)

    :timer.sleep(500)
    # check if remote node is up
    case :net_adm.ping(remote_node_a) do
      :pang ->
        assert false
      :pong -> :ok
    end

    res = ProcessHelper.find_children(Logger.Supervisor, remote_node_a)
    assert length(res) == 4
    Enum.each(res, fn pid ->
      assert node(pid) == remote_node_a
    end)
  end

  test "find_all_children() for supervisor processes on remote node" do
    :net_kernel.start([:"local2@127.0.0.1"])

    remote_node = "remote#{Enum.random(1..100)}@127.0.0.1"
    remote_node_a = String.to_atom(remote_node)
    spawn(fn ->
        System.cmd("elixir", ["--name", remote_node,
            "-e", ":timer.sleep(1000)"])
    end)

    :timer.sleep(500)
    # check if remote node is up
    case :net_adm.ping(remote_node_a) do
      :pang ->
        assert false
      :pong -> :ok
    end

    res = ProcessHelper.find_all_children(Logger.Supervisor, remote_node_a)
    assert length(res) == 5
    Enum.each(res, fn pid ->
      assert node(pid) == remote_node_a
    end)
  end
end
