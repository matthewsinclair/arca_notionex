defmodule ArcaNotionex.Commands.PullCommand do
  @moduledoc """
  Command to pull pages from Notion to local markdown files.
  """
  use Arca.Cli.Command.BaseCommand

  alias ArcaNotionex.Pull
  alias ArcaNotionex.Schemas.PullResult

  config :pull,
    name: "pull",
    about: "Pull pages from Notion to local markdown files",
    help: """
    Pulls content from Notion pages back to local markdown files.
    Supports conflict resolution strategies and multiple scope options.

    Required:
      --dir        Directory to write markdown files
      --root-page  Notion root page ID to pull from

    Scope Options (choose one):
      --scope linked-only    Only pull pages with matching local files (default)
      --scope all-children   Pull all child pages, create new files as needed
      --scope list           Pull specific pages (requires --list)
      --list <ids>           Comma-separated page IDs (with --scope list)

    Conflict Resolution:
      --conflict manual       Flag conflicts for user decision (default)
      --conflict local-wins   Skip all pulls, preserve local files
      --conflict notion-wins  Overwrite local files with Notion content
      --conflict newest-wins  Most recent modification wins

    Other:
      --dry-run    Preview changes without writing files

    Example:
      notionex pull --dir ./docs --root-page abc123
      notionex pull --dir ./docs --root-page abc123 --scope all-children
      notionex pull --dir ./docs --root-page abc123 --conflict notion-wins
      notionex pull --dir ./docs --root-page abc123 --dry-run
    """,
    options: [
      dir: [
        long: "--dir",
        short: "-d",
        help: "Directory to write markdown files",
        parser: :string,
        required: true
      ],
      root_page: [
        long: "--root-page",
        short: "-r",
        help: "Notion root page ID to pull from",
        parser: :string,
        required: true
      ],
      scope: [
        long: "--scope",
        short: "-s",
        help: "Scope: linked-only (default), all-children, list",
        parser: :string,
        required: false
      ],
      list: [
        long: "--list",
        short: "-l",
        help: "Comma-separated page IDs (requires --scope list)",
        parser: :string,
        required: false
      ],
      conflict: [
        long: "--conflict",
        short: "-c",
        help: "Resolution: manual (default), local-wins, notion-wins, newest-wins",
        parser: :string,
        required: false
      ]
    ],
    flags: [
      dry_run: [
        long: "--dry-run",
        short: "-n",
        help: "Preview changes without writing files",
        default: false
      ]
    ]

  @impl Arca.Cli.Command.CommandBehaviour
  def handle(args, _settings, _optimus) do
    dir = get_option(args, :dir)
    root_page = get_option(args, :root_page)
    scope_str = get_option(args, :scope) || "linked-only"
    list_str = get_option(args, :list)
    conflict_str = get_option(args, :conflict) || "manual"
    dry_run = get_flag(args, :dry_run)

    with {:ok, scope} <- parse_scope(scope_str),
         {:ok, page_ids} <- parse_list(list_str, scope),
         {:ok, conflict} <- parse_conflict(conflict_str) do
      opts = [
        scope: scope,
        page_ids: page_ids,
        conflict: conflict,
        dry_run: dry_run
      ]

      case Pull.pull_pages(dir, root_page, opts) do
        {:ok, result} ->
          PullResult.format(result, dry_run: dry_run)

        {:error, _reason, message} ->
          "Error: #{message}"
      end
    else
      {:error, message} ->
        "Error: #{message}"
    end
  end

  defp get_option(%{options: opts}, key), do: Map.get(opts, key)
  defp get_flag(%{flags: flags}, key), do: Map.get(flags, key, false)

  defp parse_scope("linked-only"), do: {:ok, :linked_only}
  defp parse_scope("all-children"), do: {:ok, :all_children}
  defp parse_scope("list"), do: {:ok, :list}
  defp parse_scope(other), do: {:error, "Invalid scope: #{other}. Use linked-only, all-children, or list"}

  defp parse_list(nil, :list), do: {:error, "--list is required when using --scope list"}
  defp parse_list(nil, _scope), do: {:ok, nil}

  defp parse_list(list_str, :list) do
    ids =
      list_str
      |> String.split(",")
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))

    if length(ids) > 0 do
      {:ok, ids}
    else
      {:error, "--list must contain at least one page ID"}
    end
  end

  defp parse_list(_list_str, _scope), do: {:ok, nil}

  defp parse_conflict("manual"), do: {:ok, :manual}
  defp parse_conflict("local-wins"), do: {:ok, :local_wins}
  defp parse_conflict("notion-wins"), do: {:ok, :notion_wins}
  defp parse_conflict("newest-wins"), do: {:ok, :newest_wins}

  defp parse_conflict(other) do
    {:error, "Invalid conflict strategy: #{other}. Use manual, local-wins, notion-wins, or newest-wins"}
  end
end
