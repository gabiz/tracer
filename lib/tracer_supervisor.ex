defmodule Tracer.Supervisor do
  @moduledoc """
  Supervises Tracer.Server
  """
  use Supervisor

  def start_link do
    Supervisor.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  def init(:ok) do
    children = [
      worker(Tracer.Server, [], restart: :temporary)
    ]

    supervise(children, strategy: :simple_one_for_one)
  end

  def start_server do
    Supervisor.start_child(__MODULE__, [[]])
  end

  def stop_server(pid) do
    Supervisor.terminate_child(__MODULE__, pid)
  end

end
