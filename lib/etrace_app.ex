defmodule ETrace.App do
  @moduledoc """
  ETrace Application
  """
  use Application

  def start(_type, _args) do
    ETrace.Supervisor.start_link()
  end

end
