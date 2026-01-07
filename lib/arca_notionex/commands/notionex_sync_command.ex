defmodule ArcaNotionex.Commands.NotionexSyncCommand do
  @moduledoc """
  Sync command - pushes markdown to Notion pages.
  """
  use Arca.Cli.Command.BaseCommand

  alias ArcaNotionex.Sync

  config :"notionex.sync",
    name: "notionex.sync",
    about: "Push markdown files to Notion pages",
    help: """
    Syncs a directory of markdown files to Notion.

    - Creates new pages for files without notion_id
    - Updates existing pages for files with notion_id
    - Maintains directory structure as nested pages

    Required:
      --dir        Directory containing markdown files
      --root-page  Notion page ID to sync under

    Optional:
      --dry-run    Show what would be synced without making changes

    Example:
      notionex.sync --dir ./docs --root-page abc123-def456
      notionex.sync --dir ./docs --root-page abc123 --dry-run
    """,
    options: [
      dir: [
        long: "--dir",
        short: "-d",
        help: "Directory containing markdown files",
        parser: :string,
        required: true
      ],
      root_page: [
        long: "--root-page",
        short: "-r",
        help: "Notion root page ID",
        parser: :string,
        required: true
      ]
    ],
    flags: [
      dry_run: [
        long: "--dry-run",
        short: "-n",
        help: "Show what would be synced without making changes",
        default: false
      ]
    ]

  @impl Arca.Cli.Command.CommandBehaviour
  def handle(args, _settings, _optimus) do
    dir = get_option(args, :dir)
    root_page = get_option(args, :root_page)
    dry_run = get_flag(args, :dry_run)

    case Sync.sync_directory(dir, root_page_id: root_page, dry_run: dry_run) do
      {:ok, result} ->
        format_result(result, dry_run)

      {:error, _type, reason} ->
        {:error, reason}
    end
  end

  defp get_option(%{options: opts}, key), do: Map.get(opts, key)
  defp get_flag(%{flags: flags}, key), do: Map.get(flags, key, false)

  defp format_result(result, dry_run) do
    prefix = if dry_run, do: "[DRY RUN] ", else: ""

    lines = [
      "#{prefix}Sync Complete",
      "=============",
      "Created: #{length(result.created)}",
      "Updated: #{length(result.updated)}",
      "Skipped: #{length(result.skipped)}",
      "Errors:  #{length(result.errors)}"
    ]

    details =
      []
      |> add_file_list("Created:", result.created)
      |> add_file_list("Updated:", result.updated)
      |> add_error_list("Errors:", result.errors)

    Enum.join(lines ++ details, "\n")
  end

  defp add_file_list(acc, _label, []), do: acc

  defp add_file_list(acc, label, files) do
    file_lines = Enum.map(files, fn f -> "  - #{f}" end)
    acc ++ ["", label] ++ file_lines
  end

  defp add_error_list(acc, _label, []), do: acc

  defp add_error_list(acc, label, errors) do
    error_lines = Enum.map(errors, fn e -> "  - #{e.file}: #{e.reason}" end)
    acc ++ ["", label] ++ error_lines
  end
end
