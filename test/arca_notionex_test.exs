defmodule ArcaNotionexTest do
  use ExUnit.Case

  test "returns version" do
    assert ArcaNotionex.version() == "0.1.0"
  end
end
