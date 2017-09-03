defmodule Tracer.Tool.Duration.Event do
  @moduledoc """
  Event generated by the DurationTool
  """
  alias __MODULE__

  defstruct duration: 0,
            pid: nil,
            mod: nil,
            fun: nil,
            arity: nil,
            message: nil

  defimpl String.Chars, for: Event do
    def to_string(%Event{duration: d} = event) when is_integer(d) do
      duration_str = String.pad_trailing(Integer.to_string(event.duration),
                                         20)
      "\t#{duration_str} #{inspect event.pid} " <>
        "#{inspect event.mod}.#{event.fun}/#{event.arity}" <>
        " #{message_to_string event.message}"
    end
    def to_string(event) do
      header = "#{inspect event.pid} " <>
        "#{inspect event.mod}.#{event.fun}/#{event.arity}" <>
        " #{message_to_string event.message}\n"
        step = (event.duration |> Map.values |> Enum.max) / 41
      title = String.pad_leading("value", 15) <>
                "  ------------- Distribution ------------- count\n"
      body = event.duration
      |> Enum.map(fn {key, value} ->
        String.pad_leading(Integer.to_string(key), 15) <>
        " |" <> to_bar(value, step) <> " #{value}\n"
      end) |> Enum.join("")
      header <> title <> body
    end

    defp to_bar(value, step) do
      char_num = round(value / step)
      String.duplicate("@", char_num) <> String.duplicate(" ", 41 - char_num)
    end

    defp message_to_string(nil), do: ""
    defp message_to_string(term) when is_list(term) do
      term
      |> Enum.map(fn
        [key, val] -> {key, val}
        other -> "#{inspect other}"
      end)
      |> inspect()
    end
  end

end
