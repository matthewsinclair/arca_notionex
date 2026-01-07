defmodule Mix.Tasks.Notionex do
  @moduledoc """
  Mix task bridge for Notionex CLI.

  Usage:
    mix notionex help
    mix notionex notionex.audit --dir ./docs --root-page abc123
    mix notionex notionex.sync --dir ./docs --root-page abc123
  """
  use Mix.Task
  alias Arca.Cli

  @impl Mix.Task
  @requirements ["app.config", "app.start"]
  @shortdoc "Runs the Notionex CLI"

  @doc "Invokes the Notionex CLI and passes it the supplied command line params."
  def run(args) do
    _ = Cli.main(args)
    nil
  end
end
