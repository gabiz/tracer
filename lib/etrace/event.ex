defmodule ETrace.Event do
  @moduledoc """
  Defines a generic event
  """

  defstruct event: nil

  # def to_string(event) do
  #   "#{inspect event}"
  # end

  defimpl String.Chars, for: ETrace.Event do
    def to_string(event) do
      "#{inspect event}"
    end
  end

  def format_ts(ts) do
    {{year, month, day}, {hour, minute, second}} = :calendar.now_to_datetime(ts)
    "#{inspect month}/#{inspect day}/#{inspect year}-" <>
      "#{inspect hour}:#{inspect minute}:#{inspect second}"
  end
end

defmodule ETrace.EventCall do
  @moduledoc """
  Defines a call event
  """
  alias ETrace.Event

  defstruct mod: nil, fun: nil, arity: nil,
            pid: nil,
            message: nil,
            ts: nil

  def tag, do: :call

  defimpl String.Chars, for: ETrace.EventCall do
    def to_string(event) do
      "#{Event.format_ts event.ts}: #{inspect event.pid} >> " <>
        "#{inspect event.mod}.#{Atom.to_string(event.fun)}/#{inspect event.arity} " <>
        if event.message != nil, do: " #{inspect format_message(event.message)}",
        else: ""
    end

    defp format_message(term) when is_list(term) do
      term
      |> Enum.map(fn
        [key, val] -> {key, val}
        other -> other
       end)
    end
  end
end

defmodule ETrace.EventReturnTo do
  @moduledoc """
  Defines an return_to event
  """
  alias ETrace.Event

  defstruct mod: nil, fun: nil, arity: nil,
            pid: nil,
            ts: nil

  def tag, do: :return_to

  defimpl String.Chars, for: ETrace.EventReturnTo do
    def to_string(event) do
      "#{Event.format_ts event.ts}: #{inspect event.pid} << " <>
        "#{inspect event.mod}.#{inspect event.fun}/#{inspect event.arity} " <>
        "return_to"
    end
  end
end

defmodule ETrace.EventReturnFrom do
  @moduledoc """
  Defines a return_from event
  """
  alias ETrace.Event

  defstruct mod: nil, fun: nil, arity: nil,
            pid: nil,
            return_value: nil,
            ts: nil

  def tag, do: :return_from

  defimpl String.Chars, for: ETrace.EventReturnFrom do
    def to_string(event) do
      "#{Event.format_ts event.ts}: #{inspect event.pid} << " <>
        "#{inspect event.mod}.#{inspect event.fun}/#{inspect event.arity} " <>
        "-> #{inspect event.return_value}"
    end
  end
end
