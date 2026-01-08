defmodule ArcaNotionex.Pull do
  @moduledoc """
  Pull orchestration for syncing from Notion to local markdown files.

  This is the reverse of `Sync` - it fetches pages from Notion and
  writes them to local markdown files.

  ## Workflow

  1. Resolve scope (which pages to pull based on options)
  2. For each page:
     - Fetch page metadata and blocks from Notion
     - Find matching local file (by notion_id in frontmatter)
     - Detect conflict status
     - Apply resolution strategy
     - Convert blocks to markdown
     - Create or update local file
     - Update frontmatter with sync timestamp

  ## Example

      {:ok, result} = Pull.pull_pages(
        "/path/to/docs",
        "root-page-id",
        scope: :linked_only,
        conflict: :manual
      )

  """

  alias ArcaNotionex.{Client, Conflict, Frontmatter, LinkMap}
  alias ArcaNotionex.BlocksToMarkdown
  alias ArcaNotionex.Schemas.PullResult

  @type pull_opts :: [
          scope: :linked_only | :all_children | :list,
          page_ids: [String.t()] | nil,
          conflict: Conflict.resolution_strategy(),
          dry_run: boolean()
        ]

  @doc """
  Pulls pages from Notion to local markdown files.

  ## Options

  - `:scope` - Which pages to pull (:linked_only, :all_children, :list)
  - `:page_ids` - List of page IDs (required when scope is :list)
  - `:conflict` - Conflict resolution strategy (:manual, :local_wins, :notion_wins, :newest_wins)
  - `:dry_run` - If true, don't write files, just report what would happen

  """
  @spec pull_pages(String.t(), String.t(), pull_opts()) ::
          {:ok, PullResult.t()} | {:error, atom(), String.t()}
  def pull_pages(dir, root_page_id, opts \\ []) do
    scope = Keyword.get(opts, :scope, :linked_only)
    conflict_strategy = Keyword.get(opts, :conflict, :manual)
    dry_run = Keyword.get(opts, :dry_run, false)
    page_ids = Keyword.get(opts, :page_ids, [])

    with {:ok, link_map} <- LinkMap.build(dir),
         {:ok, notion_pages} <- resolve_scope(scope, root_page_id, dir, page_ids) do
      result = PullResult.new()

      result =
        Enum.reduce(notion_pages, result, fn page_info, acc ->
          process_page(page_info, dir, link_map, conflict_strategy, dry_run, acc)
        end)

      {:ok, result}
    end
  end

  # Scope resolution

  defp resolve_scope(:linked_only, _root_page_id, dir, _page_ids) do
    # Only pull pages that have matching local files with notion_id
    {:ok, link_map} = LinkMap.build(dir)
    notion_ids = Map.keys(link_map.id_to_path)

    pages =
      Enum.map(notion_ids, fn id ->
        %{id: id, path: link_map.id_to_path[id]}
      end)

    {:ok, pages}
  end

  defp resolve_scope(:all_children, root_page_id, _dir, _page_ids) do
    # Recursively fetch all child pages from Notion
    fetch_all_child_pages(root_page_id)
  end

  defp resolve_scope(:list, _root_page_id, _dir, page_ids) when is_list(page_ids) do
    pages = Enum.map(page_ids, fn id -> %{id: id, path: nil} end)
    {:ok, pages}
  end

  defp resolve_scope(:list, _root_page_id, _dir, _) do
    {:error, :invalid_options, "--list requires page IDs"}
  end

  defp fetch_all_child_pages(page_id) do
    case Client.list_child_pages(page_id) do
      {:ok, response} ->
        pages =
          response.results
          |> Enum.filter(fn block -> block["type"] == "child_page" end)
          |> Enum.flat_map(fn block ->
            child_id = block["id"]
            title = get_in(block, ["child_page", "title"]) || "Untitled"

            # Recursively get grandchildren
            grandchildren =
              case fetch_all_child_pages(child_id) do
                {:ok, children} -> children
                {:error, _, _} -> []
              end

            [%{id: child_id, title: title, path: nil} | grandchildren]
          end)

        {:ok, pages}

      {:error, reason, msg} ->
        {:error, reason, msg}
    end
  end

  # Page processing

  defp process_page(page_info, dir, link_map, conflict_strategy, dry_run, result) do
    page_id = page_info.id

    with {:ok, page_response} <- Client.get_page(page_id),
         {:ok, blocks} <- Client.get_page_blocks(page_id) do
      # Extract page metadata
      notion_page = %{
        id: page_id,
        title: extract_page_title(page_response),
        last_edited_time: parse_datetime(page_response.raw["last_edited_time"])
      }

      # Find local file
      local_path = page_info.path || LinkMap.notion_id_to_path(link_map, page_id)
      local_file = build_local_file(local_path, dir)

      # Detect and resolve conflict
      status = Conflict.detect(local_file, notion_page)

      case Conflict.resolve(conflict_strategy, status, local_file, notion_page) do
        {:skip, _reason} ->
          path = local_path || notion_page.title
          PullResult.add_skipped(result, path)

        {:update, _page} ->
          if dry_run do
            action = if local_file, do: "update", else: "create"
            path = local_path || derive_filename(notion_page.title, dir)
            result = add_to_result(result, action, path)
            result
          else
            write_page_to_file(notion_page, blocks, local_path, dir, link_map, result)
          end

        {:conflict, entry} ->
          PullResult.add_conflict(result, entry)
      end
    else
      {:error, reason, msg} ->
        PullResult.add_error(result, page_id, reason, msg)
    end
  end

  defp build_local_file(nil, _dir), do: nil

  defp build_local_file(relative_path, dir) do
    full_path = Path.join(dir, relative_path)

    case File.stat(full_path) do
      {:ok, stat} ->
        mtime = NaiveDateTime.from_erl!(stat.mtime) |> DateTime.from_naive!("Etc/UTC")

        synced_at =
          case File.read(full_path) do
            {:ok, content} ->
              case Frontmatter.parse(content) do
                {:ok, fm, _body} -> Map.get(fm, :notion_synced_at)
                _ -> nil
              end

            _ ->
              nil
          end

        %{
          path: relative_path,
          notion_synced_at: synced_at,
          mtime: mtime
        }

      {:error, _} ->
        nil
    end
  end

  defp write_page_to_file(notion_page, blocks, local_path, dir, link_map, result) do
    # Convert blocks to markdown
    {:ok, markdown} = BlocksToMarkdown.convert(blocks, link_map: link_map)

    # Determine file path
    file_path =
      if local_path do
        local_path
      else
        derive_filename(notion_page.title, dir)
      end

    full_path = Path.join(dir, file_path)

    # Ensure directory exists
    File.mkdir_p!(Path.dirname(full_path))

    # Build frontmatter
    frontmatter = %{
      title: notion_page.title,
      notion_id: notion_page.id,
      notion_synced_at: DateTime.utc_now() |> DateTime.to_iso8601()
    }

    # Build file content
    content = build_file_content(frontmatter, markdown)

    # Write file
    case File.write(full_path, content) do
      :ok ->
        if local_path do
          PullResult.add_updated(result, file_path)
        else
          PullResult.add_created(result, file_path)
        end

      {:error, reason} ->
        PullResult.add_error(result, file_path, :write_error, "#{reason}")
    end
  end

  defp build_file_content(frontmatter, markdown) do
    yaml =
      Enum.map(frontmatter, fn {k, v} ->
        "#{k}: #{inspect(v)}"
      end)
      |> Enum.join("\n")

    "---\n#{yaml}\n---\n\n#{markdown}"
  end

  defp derive_filename(title, _dir) do
    title
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9\s-]/, "")
    |> String.replace(~r/\s+/, "-")
    |> String.slice(0, 50)
    |> Kernel.<>(".md")
  end

  defp extract_page_title(page_response) do
    case get_in(page_response.raw, ["properties", "title", "title"]) do
      [%{"plain_text" => title} | _] -> title
      _ -> "Untitled"
    end
  end

  defp parse_datetime(nil), do: nil

  defp parse_datetime(iso_string) when is_binary(iso_string) do
    case DateTime.from_iso8601(iso_string) do
      {:ok, dt, _} -> dt
      _ -> nil
    end
  end

  defp add_to_result(result, "create", path), do: PullResult.add_created(result, path)
  defp add_to_result(result, "update", path), do: PullResult.add_updated(result, path)
end
