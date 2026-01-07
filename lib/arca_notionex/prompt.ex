defmodule ArcaNotionex.Prompt do
  @moduledoc """
  Custom prompt formatting for the Notionex REPL.
  """

  @doc """
  Generates the REPL prompt string.

  Format: `N> ` where N is the command history count.
  """
  @spec text(map()) :: String.t()
  def text(context) do
    history_count = Map.get(context, :history_count, 0)
    "\n#{history_count}> "
  end
end
