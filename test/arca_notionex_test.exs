defmodule ArcaNotionexTest do
  use ExUnit.Case

  test "returns version from config" do
    version = ArcaNotionex.version()
    assert is_binary(version)
    assert Regex.match?(~r/^\d+\.\d+\.\d+$/, version)
  end
end
