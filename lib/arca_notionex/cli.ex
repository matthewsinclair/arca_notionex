defmodule ArcaNotionex.CLI do
  @moduledoc """
  Entry point for the notionex escript.

  This module provides the main/1 function required by escript
  to create a standalone executable.
  """

  @doc """
  Main entry point for the escript.

  Delegates to Arca.Cli.main/1 to handle command parsing and execution.
  """
  def main(args) do
    # Ensure the application is started
    Application.ensure_all_started(:arca_notionex)

    # Delegate to the CLI framework
    Arca.Cli.main(args)
  end
end
