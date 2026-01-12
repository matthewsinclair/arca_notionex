defmodule ArcaNotionex.Commands.SyncCommand do
  @moduledoc """
  Sync command - pushes markdown to Notion pages.
  """
  use Arca.Cli.Command.BaseCommand

  alias ArcaNotionex.Sync

  config :sync,
    name: "sync",
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
      --dry-run          Show what would be synced without making changes
      --relink           Resolve internal .md links to Notion page URLs
                         (requires prior sync to populate notion_ids)
      --skip-child-links Skip links to filesystem subdirectories
                         (use when subdirs are Notion child pages)

    Workflow for internal links:
      1. notionex sync --dir ./docs --root-page abc123
         (First sync creates pages, links will be broken)
      2. notionex sync --dir ./docs --root-page abc123 --relink
         (Second sync resolves internal .md links to Notion URLs)

    Example:
      notionex sync --dir ./docs --root-page abc123-def456
      notionex sync --dir ./docs --root-page abc123 --dry-run
      notionex sync --dir ./docs --root-page abc123 --relink
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
      ],
      relink: [
        long: "--relink",
        short: "-l",
        help: "Resolve internal .md links to Notion page URLs",
        default: false
      ],
      skip_child_links: [
        long: "--skip-child-links",
        help: "Skip links to filesystem subdirectories (use when subdirs are Notion children)",
        default: false
      ]
    ]

  @impl Arca.Cli.Command.CommandBehaviour
  def handle(args, _settings, _optimus) do
    dir = get_option(args, :dir)
    root_page = get_option(args, :root_page)
    dry_run = get_flag(args, :dry_run)
    relink = get_flag(args, :relink)
    skip_child_links = get_flag(args, :skip_child_links)

    case Sync.sync_directory(dir,
           root_page_id: root_page,
           dry_run: dry_run,
           relink: relink,
           skip_child_links: skip_child_links
         ) do
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
