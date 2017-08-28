defmodule ETrace.ReporterRouter do
  @moduledoc """
  Maps reporter_type to reporter modules
  """

  alias ETrace.{CountReporter, DurationReporter,
                DisplayReporter, CallSeqReporter}

  def router(:count), do: CountReporter
  def router(:display), do: DisplayReporter
  def router(:duration), do: DurationReporter
  def router(:call_seq), do: CallSeqReporter
  def router(nil), do: DisplayReporter

end
