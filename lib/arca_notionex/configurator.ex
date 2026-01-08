defmodule ArcaNotionex.Configurator do
  @moduledoc """
  Configures the Notionex CLI commands.
  """
  use Arca.Cli.Configurator.BaseConfigurator

  config :notionex,
    commands: [
      Arca.Cli.Commands.ReplCommand,
      ArcaNotionex.Commands.AuditCommand,
      ArcaNotionex.Commands.SyncCommand,
      ArcaNotionex.Commands.PrepareCommand,
      ArcaNotionex.Commands.PullCommand
    ],
    author: "matts",
    about: "Notion Markdown Sync CLI",
    description: "Sync markdown files to Notion pages"
end
