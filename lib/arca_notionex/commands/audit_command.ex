defmodule ArcaNotionex.Commands.AuditCommand do
  @moduledoc """
  Audit command - compares local markdown with Notion state.
  """
  use Arca.Cli.Command.BaseCommand

  alias Arca.Cli.Ctx
  alias ArcaNotionex.Audit

  config :audit,
    name: "audit",
    about: "Compare local markdown files vs Notion state",
    help: """
    Audits a directory of markdown files against Notion pages.
    Shows which files need to be created, updated, or are in sync.

    Required:
      --dir        Directory containing markdown files
      --root-page  Notion page ID to audit against

    Optional:
      --status     Filter by status (synced, stale, local-only, notion-only)
      --json       Output as JSON instead of table

    Example:
      notionex audit --dir ./docs --root-page abc123-def456
      notionex audit --dir ./docs --root-page abc123 --status stale
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
      ],
      status: [
        long: "--status",
        short: "-s",
        help: "Filter by status",
        parser: :string,
        required: false
      ]
    ],
    flags: [
      json: [
        long: "--json",
        help: "Output as JSON instead of table",
        default: false
      ]
    ]

  @impl Arca.Cli.Command.CommandBehaviour
  def handle(args, settings, _optimus) do
    ctx = Ctx.new(:audit, settings)
    dir = get_option(args, :dir)
    root_page = get_option(args, :root_page)
    status = parse_status(get_option(args, :status))
    json_output = get_flag(args, :json)

    case Audit.audit_directory(dir, root_page_id: root_page, status: status) do
      {:ok, entries} ->
        if json_output do
          ctx
          |> Ctx.add_output({:text, format_json(entries)})
          |> Ctx.complete(:ok)
        else
          {table_rows, summary} = Audit.format_for_ctx(entries)

          ctx
          |> Ctx.add_output({:table, table_rows, [has_headers: true]})
          |> Ctx.add_output({:info, summary})
          |> Ctx.with_cargo(%{entries: length(entries)})
          |> Ctx.complete(:ok)
        end

      {:error, _type, reason} ->
        ctx
        |> Ctx.add_output({:error, reason})
        |> Ctx.complete(:error)
    end
  end

  defp get_option(%{options: opts}, key), do: Map.get(opts, key)
  defp get_flag(%{flags: flags}, key), do: Map.get(flags, key, false)

  defp parse_status(nil), do: nil
  defp parse_status("synced"), do: :synced
  defp parse_status("stale"), do: :stale
  defp parse_status("local-only"), do: :local_only
  defp parse_status("notion-only"), do: :notion_only
  defp parse_status(_), do: nil

  defp format_json(entries) do
    entries
    |> Enum.map(fn entry ->
      %{
        file: entry.file,
        title: entry.title,
        local_status: entry.local_status,
        notion_status: entry.notion_status,
        notion_id: entry.notion_id,
        action_needed: entry.action_needed
      }
    end)
    |> Jason.encode!(pretty: true)
  end
end
