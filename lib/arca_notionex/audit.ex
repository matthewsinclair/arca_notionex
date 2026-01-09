defmodule ArcaNotionex.Audit do
  @moduledoc """
  Compares local markdown files with Notion state.
  Generates tabular audit report.
  """

  alias ArcaNotionex.{Frontmatter, Client, Sync}
  alias ArcaNotionex.Schemas.{AuditEntry, FileEntry}

  @type audit_opts :: [
          root_page_id: String.t(),
          status: atom() | nil
        ]

  @doc """
  Audits a directory against Notion.

  ## Options

  - `:root_page_id` - Required. The Notion page ID to audit against.
  - `:status` - Optional. Filter by status (:synced, :stale, :local_only, :notion_only)

  ## Returns

  `{:ok, [%AuditEntry{}]}` with comparison results.
  """
  @spec audit_directory(String.t(), audit_opts()) ::
          {:ok, [AuditEntry.t()]} | {:error, atom(), String.t()}
  def audit_directory(dir_path, opts) do
    root_page_id = Keyword.fetch!(opts, :root_page_id)
    status_filter = Keyword.get(opts, :status)

    with {:ok, local_files} <- scan_local_files(dir_path),
         {:ok, notion_pages} <- scan_notion_pages(root_page_id) do
      entries =
        compare_states(local_files, notion_pages)
        |> maybe_filter_by_status(status_filter)

      {:ok, entries}
    end
  end

  @doc """
  Formats audit results for Ctx table output.
  Returns {table_rows, summary_string} where table_rows is a list of lists
  with the first row being headers.
  """
  @spec format_for_ctx([AuditEntry.t()]) :: {[[String.t()]], String.t()}
  def format_for_ctx(entries) do
    headers = ["File", "Title", "Local", "Notion", "Synced At", "Action"]

    rows =
      Enum.map(entries, fn entry ->
        [
          entry.file,
          entry.title || "",
          format_local_status(entry.local_status),
          format_notion_status(entry.notion_status, entry.notion_id),
          format_datetime(entry.synced_at),
          format_action(entry.action_needed)
        ]
      end)

    table_rows = [headers | rows]
    summary = format_summary(entries)

    {table_rows, summary}
  end

  @doc """
  Formats audit results as a table string.
  """
  @spec format_table([AuditEntry.t()]) :: String.t()
  def format_table(entries) do
    headers = ["File", "Title", "Local", "Notion", "Synced At", "Action"]

    rows =
      Enum.map(entries, fn entry ->
        [
          entry.file,
          truncate(entry.title, 30),
          format_local_status(entry.local_status),
          format_notion_status(entry.notion_status, entry.notion_id),
          format_datetime(entry.synced_at),
          format_action(entry.action_needed)
        ]
      end)

    TableRex.Table.new(rows, headers)
    |> TableRex.Table.render!(horizontal_style: :all, vertical_style: :all)
  end

  @doc """
  Returns a summary string of the audit results.
  """
  @spec format_summary([AuditEntry.t()]) :: String.t()
  def format_summary(entries) do
    counts =
      Enum.reduce(entries, %{synced: 0, stale: 0, local_only: 0, notion_only: 0}, fn entry, acc ->
        status = AuditEntry.status(entry)
        Map.update(acc, status, 1, &(&1 + 1))
      end)

    "Summary: #{counts.synced} synced, #{counts.stale} stale, #{counts.local_only} local-only, #{counts.notion_only} notion-only"
  end

  # Private functions

  defp scan_local_files(dir_path) do
    case Sync.discover_files(dir_path) do
      {:ok, files} ->
        entries =
          Enum.map(files, fn file ->
            load_frontmatter(file)
          end)

        {:ok, entries}

      error ->
        error
    end
  end

  defp load_frontmatter(%FileEntry{} = file) do
    case File.read(file.path) do
      {:ok, content} ->
        case Frontmatter.parse(content) do
          {:ok, fm, _body} ->
            FileEntry.with_frontmatter(file, fm)

          _ ->
            file
        end

      _ ->
        file
    end
  end

  defp scan_notion_pages(root_page_id) do
    scan_notion_pages_recursive(root_page_id, [])
  end

  defp scan_notion_pages_recursive(page_id, acc) do
    case Client.list_child_pages(page_id) do
      {:ok, response} ->
        pages =
          response.results
          |> Enum.filter(fn block -> Map.get(block, "type") == "child_page" end)
          |> Enum.map(fn block ->
            %{
              id: Map.get(block, "id"),
              title: get_in(block, ["child_page", "title"]) || "Untitled",
              parent_id: page_id
            }
          end)

        # Recursively scan children
        Enum.reduce_while(pages, {:ok, acc ++ pages}, fn page, {:ok, current_acc} ->
          case scan_notion_pages_recursive(page.id, current_acc) do
            {:ok, updated_acc} -> {:cont, {:ok, updated_acc}}
            error -> {:halt, error}
          end
        end)

      {:error, type, reason} ->
        {:error, type, reason}
    end
  end

  defp compare_states(local_files, notion_pages) do
    # Build a map of notion_id -> page
    notion_map = Map.new(notion_pages, fn p -> {p.id, p} end)

    # Build set of local notion_ids
    local_notion_ids = MapSet.new(local_files, &FileEntry.notion_id/1)

    # Build set of local directory paths (humanized for matching)
    local_directories =
      local_files
      |> Enum.map(& &1.parent_path)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()
      |> MapSet.new(&humanize_dirname/1)

    # Build set of page IDs that are parents (have children)
    parent_page_ids =
      notion_pages
      |> Enum.map(& &1.parent_id)
      |> Enum.reject(&is_nil/1)
      |> MapSet.new()

    # Create entries for local files
    local_entries =
      Enum.map(local_files, fn file ->
        notion_id = FileEntry.notion_id(file)
        notion_page = if notion_id, do: Map.get(notion_map, notion_id)

        build_audit_entry(file, notion_page)
      end)

    # Classify Notion-only pages as orphans or directory pages
    orphan_entries =
      notion_pages
      |> Enum.reject(fn p -> MapSet.member?(local_notion_ids, p.id) end)
      |> Enum.map(fn p ->
        is_directory_page =
          MapSet.member?(local_directories, p.title) and
            MapSet.member?(parent_page_ids, p.id)

        if is_directory_page do
          AuditEntry.directory_page(p.id, p.title)
        else
          AuditEntry.notion_only(p.id, p.title)
        end
      end)

    local_entries ++ orphan_entries
  end

  defp humanize_dirname(name) do
    name
    |> String.replace(~r/[-_]/, " ")
    |> String.split()
    |> Enum.map(&String.capitalize/1)
    |> Enum.join(" ")
  end

  defp build_audit_entry(%FileEntry{} = file, notion_page) do
    notion_id = FileEntry.notion_id(file)
    title = FileEntry.title(file)
    synced_at = get_synced_at(file)

    cond do
      notion_id == nil ->
        AuditEntry.local_only(file.relative_path, title)

      notion_page == nil ->
        # Has notion_id but page not found - could be deleted or outside scan scope
        AuditEntry.unverified(file.relative_path, title, notion_id, synced_at)

      needs_update?(synced_at) ->
        AuditEntry.stale(file.relative_path, title, notion_id, synced_at)

      true ->
        AuditEntry.synced(file.relative_path, title, notion_id, synced_at)
    end
  end

  defp get_synced_at(%FileEntry{frontmatter: nil}), do: nil
  defp get_synced_at(%FileEntry{frontmatter: fm}), do: fm.notion_synced_at

  defp needs_update?(nil), do: true

  defp needs_update?(%DateTime{} = synced_at) do
    # Consider stale if synced more than 24 hours ago
    DateTime.diff(DateTime.utc_now(), synced_at, :hour) > 24
  end

  defp maybe_filter_by_status(entries, nil), do: entries

  defp maybe_filter_by_status(entries, status) do
    Enum.filter(entries, fn entry ->
      AuditEntry.status(entry) == status
    end)
  end

  defp format_local_status(:exists), do: "Y"
  defp format_local_status(:missing), do: "-"

  defp format_notion_status(:exists, id), do: "Y (#{truncate(id, 8)})"
  defp format_notion_status(:unknown, id) when is_binary(id), do: "? (#{truncate(id, 8)})"
  defp format_notion_status(:missing, _), do: "-"
  defp format_notion_status(:unknown, _), do: "?"

  defp format_action(:create), do: "CREATE"
  defp format_action(:update), do: "UPDATE"
  defp format_action(:delete), do: "DELETE"
  defp format_action(:none), do: "-"

  defp format_datetime(nil), do: "-"
  defp format_datetime(%DateTime{} = dt), do: Calendar.strftime(dt, "%Y-%m-%d %H:%M")

  defp truncate(nil, _), do: ""
  defp truncate(str, max) when byte_size(str) <= max, do: str
  defp truncate(str, max), do: String.slice(str, 0, max - 3) <> "..."
end
