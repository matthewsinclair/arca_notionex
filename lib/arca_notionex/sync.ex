defmodule ArcaNotionex.Sync do
  @moduledoc """
  Orchestrates markdown to Notion synchronization.

  Handles:
  - Directory traversal
  - Hierarchical page creation (subdirectories become child pages)
  - Update vs create logic
  - Frontmatter updates after sync
  """

  alias ArcaNotionex.{Frontmatter, AstToBlocks, Client}
  alias ArcaNotionex.Schemas.{FileEntry, SyncResult}

  @type sync_opts :: [
          root_page_id: String.t(),
          dry_run: boolean()
        ]

  @doc """
  Syncs a directory of markdown files to Notion.

  ## Options

  - `:root_page_id` - Required. The Notion page ID to sync under.
  - `:dry_run` - If true, preview changes without modifying anything.

  ## Returns

  `{:ok, %SyncResult{}}` with counts of created, updated, skipped, and errors.
  """
  @spec sync_directory(String.t(), sync_opts()) ::
          {:ok, SyncResult.t()} | {:error, atom(), String.t()}
  def sync_directory(dir_path, opts) do
    root_page_id = Keyword.fetch!(opts, :root_page_id)
    dry_run = Keyword.get(opts, :dry_run, false)

    with {:ok, files} <- discover_files(dir_path),
         {:ok, result} <- sync_files(files, dir_path, root_page_id, dry_run) do
      {:ok, result}
    end
  end

  @doc """
  Syncs a single markdown file to Notion.
  """
  @spec sync_file(String.t(), String.t(), keyword()) ::
          {:ok, :created | :updated | :skipped, String.t() | nil} | {:error, atom(), String.t()}
  def sync_file(file_path, parent_page_id, opts \\ []) do
    dry_run = Keyword.get(opts, :dry_run, false)

    with {:ok, content} <- File.read(file_path),
         {:ok, frontmatter, body} <- Frontmatter.parse(content),
         {:ok, block_chunks} <- AstToBlocks.convert(body) do
      blocks = List.flatten(block_chunks)
      title = frontmatter.title || derive_title(file_path)

      cond do
        dry_run ->
          action = if frontmatter.notion_id, do: :updated, else: :created
          {:ok, action, "[dry-run] Would #{action}: #{title}"}

        frontmatter.notion_id != nil ->
          update_existing_page(file_path, frontmatter.notion_id, blocks)

        true ->
          create_new_page(file_path, parent_page_id, title, blocks)
      end
    end
  end

  # File discovery

  @doc """
  Discovers all markdown files in a directory recursively.
  """
  @spec discover_files(String.t()) :: {:ok, [FileEntry.t()]} | {:error, atom(), String.t()}
  def discover_files(dir_path) do
    if File.dir?(dir_path) do
      files =
        dir_path
        |> Path.join("**/*.md")
        |> Path.wildcard()
        |> Enum.map(&FileEntry.new(&1, dir_path))
        |> Enum.sort_by(& &1.depth)

      {:ok, files}
    else
      {:error, :not_a_directory, "#{dir_path} is not a directory"}
    end
  end

  # Private functions

  defp sync_files(files, base_path, root_page_id, dry_run) do
    # Track directory -> page ID mapping
    page_map = %{"" => root_page_id}
    result = SyncResult.new()

    {final_result, _final_map} =
      Enum.reduce(files, {result, page_map}, fn file, {res, pmap} ->
        # Ensure parent directory pages exist
        {pmap, parent_id} = ensure_parent_pages(file, pmap, root_page_id, base_path, dry_run)

        # Sync the file
        case sync_file(file.path, parent_id, dry_run: dry_run) do
          {:ok, :created, _} ->
            {SyncResult.add_created(res, file.relative_path), pmap}

          {:ok, :updated, _} ->
            {SyncResult.add_updated(res, file.relative_path), pmap}

          {:ok, :skipped, _} ->
            {SyncResult.add_skipped(res, file.relative_path), pmap}

          {:error, _type, reason} ->
            {SyncResult.add_error(res, file.relative_path, reason), pmap}
        end
      end)

    {:ok, final_result}
  end

  defp ensure_parent_pages(
         %FileEntry{parent_path: nil},
         page_map,
         root_page_id,
         _base_path,
         _dry_run
       ) do
    {page_map, root_page_id}
  end

  defp ensure_parent_pages(
         %FileEntry{parent_path: parent_path},
         page_map,
         root_page_id,
         base_path,
         dry_run
       ) do
    if Map.has_key?(page_map, parent_path) do
      {page_map, Map.get(page_map, parent_path)}
    else
      # Need to create directory pages
      create_directory_pages(parent_path, page_map, root_page_id, base_path, dry_run)
    end
  end

  defp create_directory_pages(dir_path, page_map, root_page_id, _base_path, dry_run) do
    parts = Path.split(dir_path)

    Enum.reduce(parts, {page_map, root_page_id, ""}, fn part, {pmap, parent_id, current_path} ->
      new_path = if current_path == "", do: part, else: Path.join(current_path, part)

      if Map.has_key?(pmap, new_path) do
        {pmap, Map.get(pmap, new_path), new_path}
      else
        # Create directory page
        dir_title = humanize_dirname(part)

        page_id =
          if dry_run do
            "dry-run-#{new_path}"
          else
            case Client.create_page(parent_id, dir_title, []) do
              {:ok, response} -> response.id
              {:error, _, _} -> parent_id
            end
          end

        new_map = Map.put(pmap, new_path, page_id)
        {new_map, page_id, new_path}
      end
    end)
    |> then(fn {pmap, page_id, _path} -> {pmap, page_id} end)
  end

  defp create_new_page(file_path, parent_page_id, title, blocks) do
    case Client.create_page(parent_page_id, title, blocks) do
      {:ok, response} ->
        # Update frontmatter with notion_id
        Frontmatter.set_notion_id(file_path, response.id)
        {:ok, :created, response.id}

      {:error, type, reason} ->
        {:error, type, reason}
    end
  end

  defp update_existing_page(file_path, notion_id, blocks) do
    case Client.update_page_blocks(notion_id, blocks) do
      {:ok, _} ->
        Frontmatter.update_synced_at(file_path)
        {:ok, :updated, notion_id}

      {:error, type, reason} ->
        {:error, type, reason}
    end
  end

  defp derive_title(file_path) do
    file_path
    |> Path.basename(".md")
    |> humanize_dirname()
  end

  defp humanize_dirname(name) do
    name
    |> String.replace(~r/[-_]/, " ")
    |> String.split()
    |> Enum.map(&String.capitalize/1)
    |> Enum.join(" ")
  end
end
