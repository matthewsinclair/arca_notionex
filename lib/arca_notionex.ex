defmodule ArcaNotionex do
  @moduledoc """
  ArcaNotionex - Sync markdown files to Notion pages.

  This CLI tool provides:
  - `notionex.audit` - Compare local markdown files vs Notion state
  - `notionex.sync` - Push markdown content to Notion pages

  ## Configuration

  Set the `NOTION_API_TOKEN` environment variable with your Notion integration token.
  """

  @doc """
  Returns the application version.
  """
  @spec version() :: String.t()
  def version do
    "0.1.0"
  end
end
