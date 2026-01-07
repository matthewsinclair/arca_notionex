defmodule ArcaNotionex.Commands.NotionexCommand do
  @moduledoc """
  Namespace command for Notionex CLI.
  """
  use Arca.Cli.Command.BaseCommand

  config :notionex,
    name: "notionex",
    about: "Notion markdown sync commands",
    help: """
    Notionex - Sync markdown files to Notion pages.

    Available subcommands:
      notionex.prepare - Add frontmatter to markdown files
      notionex.audit   - Compare local files vs Notion state
      notionex.sync    - Push markdown to Notion pages

    Environment:
      NOTION_API_TOKEN - Required. Your Notion integration token.

    Example:
      notionex.prepare --dir ./docs --dry-run
      notionex.audit --dir ./docs --root-page abc123
      notionex.sync --dir ./docs --root-page abc123 --dry-run
    """

  @impl Arca.Cli.Command.CommandBehaviour
  def handle(_args, _settings, _optimus) do
    """
    Notionex - Sync markdown files to Notion

    Commands:
      notionex.prepare - Add frontmatter to markdown files
      notionex.audit   - Compare local markdown vs Notion state
      notionex.sync    - Push markdown to Notion pages

    Use --help with any command for details.
    """
  end
end
