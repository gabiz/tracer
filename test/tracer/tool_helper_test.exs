defmodule Tracer.ToolHelper.Test do
  use ExUnit.Case

  alias Tracer.ToolHelper

  test "to_mfa() accepts an mfa tuple" do
    assert ToolHelper.to_mfa({Map, :new, 0}) == {Map, :new, 0}
  end

  test "to_mfa() accepts a module name" do
    assert ToolHelper.to_mfa(Map) == {Map, :_, :_}
    assert ToolHelper.to_mfa(:_) == {:_, :_, :_}
  end

  test "to_mfa() accepts a function" do
    assert ToolHelper.to_mfa(&Map.new/0) == {Map, :new, 0}
  end

  test "to_mfa() fails when receiving a fn" do
    assert ToolHelper.to_mfa(fn -> :foo end) ==
              {:error, :not_an_external_function}
  end

  test "to_mfa() fails when receiving an invalid mfa" do
    assert ToolHelper.to_mfa(%{a: :foo}) == {:error, :invalid_mfa}
  end
end
