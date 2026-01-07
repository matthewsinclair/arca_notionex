defmodule ArcaNotionex.Configurator do
  @moduledoc """
  Configures the Notionex CLI commands.
  """
  use Arca.Cli.Configurator.BaseConfigurator

  config :notionex,
    commands: [
      Arca.Cli.Commands.ReplCommand,
      ArcaNotionex.Commands.NotionexCommand,
      ArcaNotionex.Commands.NotionexAuditCommand,
      ArcaNotionex.Commands.NotionexSyncCommand,
      ArcaNotionex.Commands.NotionexPrepareCommand
    ],
    author: "matts",
    about: "Notion Markdown Sync CLI",
    description: "Sync markdown files to Notion pages",
    version: "0.1.0"
end
