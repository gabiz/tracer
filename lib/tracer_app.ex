defmodule Tracer.App do
  @moduledoc """
  Tracer Application
  """
  use Application

  def start(_type, _args) do
    Tracer.Supervisor.start_link()
  end

end
