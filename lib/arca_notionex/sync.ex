defmodule ArcaNotionex.Sync do
  @moduledoc """
  Orchestrates markdown to Notion synchronization.

  Handles:
  - Directory traversal
  - Hierarchical page creation (subdirectories become child pages)
  - Update vs create logic
  - Frontmatter updates after sync
  """

  alias ArcaNotionex.{Frontmatter, AstToBlocks, Client, LinkMap}
  alias ArcaNotionex.Schemas.{FileEntry, SyncResult}

  @type sync_opts :: [
          root_page_id: String.t(),
          dry_run: boolean(),
          relink: boolean()
        ]

  @doc """
  Syncs a directory of markdown files to Notion.

  ## Options

  - `:root_page_id` - Required. The Notion page ID to sync under.
  - `:dry_run` - If true, preview changes without modifying anything.
  - `:relink` - If true, resolve internal .md links to Notion URLs.

  ## Returns

  `{:ok, %SyncResult{}}` with counts of created, updated, skipped, and errors.
  """
  @spec sync_directory(String.t(), sync_opts()) ::
          {:ok, SyncResult.t()} | {:error, atom(), String.t()}
  def sync_directory(dir_path, opts) do
    root_page_id = Keyword.fetch!(opts, :root_page_id)
    dry_run = Keyword.get(opts, :dry_run, false)
    relink = Keyword.get(opts, :relink, false)

    with {:ok, files} <- discover_files(dir_path),
         :ok <- validate_unique_titles(files, dir_path) do
      if relink do
        sync_with_relink(files, dir_path, root_page_id, dry_run)
      else
        # Single pass without link resolution
        sync_opts = [dry_run: dry_run, link_map: nil, base_dir: dir_path]
        sync_files(files, dir_path, root_page_id, sync_opts)
      end
    end
  end

  # Handle --relink with automatic two-pass when needed
  defp sync_with_relink(files, dir_path, root_page_id, dry_run) do
    # Check if any files need creation (no notion_id)
    new_files = Enum.filter(files, &file_needs_creation?(&1.path))

    if Enum.empty?(new_files) do
      # All files have notion_ids - single pass with link resolution
      IO.puts("All files have notion_ids - resolving links in single pass")
      link_map = build_link_map_safe(dir_path)
      sync_opts = [dry_run: dry_run, link_map: link_map, base_dir: dir_path]
      sync_files(files, dir_path, root_page_id, sync_opts)
    else
      # Two-pass sync needed
      IO.puts("\nPass 1/2: Creating pages (#{length(new_files)} new files)")

      # Pass 1: Sync WITHOUT link resolution to create pages
      sync_opts_pass1 = [dry_run: dry_run, link_map: nil, base_dir: dir_path]
      {:ok, result1} = sync_files(files, dir_path, root_page_id, sync_opts_pass1)

      if dry_run do
        {:ok, result1}
      else
        IO.puts("\nPass 2/2: Resolving links")

        # Rebuild link map now that notion_ids exist
        link_map = build_link_map_safe(dir_path)

        # Pass 2: Re-sync to update with resolved links
        sync_opts_pass2 = [dry_run: dry_run, link_map: link_map, base_dir: dir_path]
        {:ok, result2} = sync_files(files, dir_path, root_page_id, sync_opts_pass2)

        # Merge results: created from pass1, updated from pass2
        {:ok, merge_sync_results(result1, result2)}
      end
    end
  end

  # Check if a file needs creation (no notion_id)
  defp file_needs_creation?(file_path) do
    case read_and_parse_file(file_path) do
      {:ok, %{notion_id: notion_id}, _body} when is_binary(notion_id) -> false
      _ -> true
    end
  end

  defp build_link_map_safe(dir_path) do
    case LinkMap.build(dir_path) do
      {:ok, map} -> map
      {:error, _, _} -> LinkMap.empty()
    end
  end

  defp merge_sync_results(r1, r2) do
    %SyncResult{
      created: r1.created,
      updated: r2.updated,
      skipped: r2.skipped,
      errors: r1.errors ++ r2.errors
    }
  end

  @doc """
  Syncs a single markdown file to Notion.

  ## Options

  - `:dry_run` - Preview without making changes
  - `:link_map` - LinkMap for resolving internal .md links (requires :base_dir)
  - `:base_dir` - Base directory for computing relative paths
  """
  @spec sync_file(String.t(), String.t(), keyword()) ::
          {:ok, :created | :updated | :skipped, String.t() | nil} | {:error, atom(), String.t()}
  def sync_file(file_path, parent_page_id, opts \\ []) do
    dry_run = Keyword.get(opts, :dry_run, false)
    link_map = Keyword.get(opts, :link_map)
    base_dir = Keyword.get(opts, :base_dir)

    # Compute relative path for link resolution
    current_file =
      if base_dir do
        Path.relative_to(file_path, base_dir)
      else
        file_path
      end

    # Build convert options
    convert_opts =
      if link_map do
        [link_map: link_map, current_file: current_file]
      else
        []
      end

    with {:ok, content} <- File.read(file_path),
         {:ok, frontmatter, body} <- Frontmatter.parse(content),
         {:ok, block_chunks} <- AstToBlocks.convert(body, convert_opts) do
      blocks = List.flatten(block_chunks)
      title = frontmatter.title || derive_title(file_path)

      sync_action(file_path, parent_page_id, title, blocks, body, frontmatter, dry_run)
    end
  end

  # Dry-run mode: preview what would happen
  defp sync_action(_file_path, _parent_id, title, _blocks, _body, frontmatter, true = _dry_run) do
    action = select_action(frontmatter.notion_id)
    {:ok, action, "[dry-run] Would #{action}: #{title}"}
  end

  # Live mode: existing page (has notion_id) - check if content changed
  defp sync_action(file_path, _parent_id, _title, blocks, body, %{notion_id: notion_id, content_hash: stored_hash}, false)
       when is_binary(notion_id) do
    if Frontmatter.content_changed?(body, stored_hash) do
      update_existing_page(file_path, notion_id, blocks, body)
    else
      {:ok, :skipped, notion_id}
    end
  end

  # Live mode: new page (no notion_id) - create it
  defp sync_action(file_path, parent_id, title, blocks, body, _frontmatter, false) do
    create_new_page(file_path, parent_id, title, blocks, body)
  end

  defp select_action(nil), do: :created
  defp select_action(_notion_id), do: :updated

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

  @doc """
  Validates that titles are unique within each directory.

  Reads frontmatter from each file to determine its effective title,
  then checks for duplicates within each parent directory.

  Cross-directory duplicates are allowed (different contexts).

  ## Examples

      iex> Sync.validate_unique_titles([file1, file2], "/base")
      :ok

      iex> Sync.validate_unique_titles([dupe1, dupe2], "/base")
      {:error, :duplicate_titles, "..."}
  """
  @spec validate_unique_titles([FileEntry.t()], String.t()) :: :ok | {:error, atom(), String.t()}
  def validate_unique_titles(files, _base_dir) do
    # Build list of {parent_path, title, relative_path} tuples
    file_titles =
      files
      |> Enum.map(fn file ->
        title = get_file_title(file.path, file.relative_path)
        {file.parent_path, title, file.relative_path}
      end)

    # Group by parent directory and find duplicates within each
    duplicates =
      file_titles
      |> Enum.group_by(fn {parent, _title, _path} -> parent end)
      |> Enum.flat_map(fn {parent_path, entries} ->
        # Within each directory, find duplicate titles
        entries
        |> Enum.group_by(fn {_parent, title, _path} -> title end)
        |> Enum.filter(fn {_title, entries} -> length(entries) > 1 end)
        |> Enum.map(fn {title, entries} ->
          paths = Enum.map(entries, fn {_, _, path} -> path end) |> Enum.join(", ")
          dir_name = parent_path || "(root)"
          "In '#{dir_name}': duplicate title '#{title}' in files: #{paths}"
        end)
      end)

    case duplicates do
      [] -> :ok
      errors -> {:error, :duplicate_titles, Enum.join(errors, "\n")}
    end
  end

  # Gets the effective title for a file by reading its frontmatter
  defp get_file_title(file_path, relative_path) do
    file_path
    |> File.read()
    |> extract_title_from_file(relative_path)
  end

  defp extract_title_from_file({:ok, content}, relative_path) do
    content
    |> Frontmatter.parse()
    |> extract_title_from_parsed(relative_path)
  end

  defp extract_title_from_file({:error, _}, relative_path) do
    Frontmatter.derive_title_from_path(relative_path)
  end

  defp extract_title_from_parsed({:ok, %{title: title}, _body}, _relative_path)
       when is_binary(title) and title != "" and title != "Index" do
    title
  end

  defp extract_title_from_parsed({:ok, _frontmatter, _body}, relative_path) do
    Frontmatter.derive_title_from_path(relative_path)
  end

  defp extract_title_from_parsed({:error, _, _}, relative_path) do
    Frontmatter.derive_title_from_path(relative_path)
  end

  # Private functions

  defp sync_files(files, base_path, root_page_id, sync_opts) do
    # Track directory -> page ID mapping
    page_map = %{"" => root_page_id}
    result = SyncResult.new()
    dry_run = Keyword.get(sync_opts, :dry_run, false)

    {final_result, _final_map} =
      Enum.reduce(files, {result, page_map}, fn file, {res, pmap} ->
        # Read file once and branch based on notion_id presence
        case read_and_parse_file(file.path) do
          {:ok, frontmatter, _body} ->
            sync_single_file(
              file,
              frontmatter,
              res,
              pmap,
              root_page_id,
              base_path,
              sync_opts,
              dry_run
            )

          {:error, reason} ->
            {SyncResult.add_error(res, file.relative_path, reason), pmap}
        end
      end)

    {:ok, final_result}
  end

  # Single file read and parse
  defp read_and_parse_file(file_path) do
    with {:ok, content} <- File.read(file_path),
         {:ok, frontmatter, body} <- Frontmatter.parse(content) do
      {:ok, frontmatter, body}
    else
      {:error, reason} -> {:error, "Failed to read: #{inspect(reason)}"}
      {:error, _type, reason} -> {:error, reason}
    end
  end

  # Pattern-matched: files WITH notion_id (updates) - skip ensure_parent_pages
  defp sync_single_file(
         file,
         %{notion_id: notion_id},
         res,
         pmap,
         root_page_id,
         _base_path,
         sync_opts,
         _dry_run
       )
       when is_binary(notion_id) do
    case sync_file(file.path, root_page_id, sync_opts) do
      {:ok, :created, _} -> {SyncResult.add_created(res, file.relative_path), pmap}
      {:ok, :updated, _} -> {SyncResult.add_updated(res, file.relative_path), pmap}
      {:ok, :skipped, _} -> {SyncResult.add_skipped(res, file.relative_path), pmap}
      {:error, _type, reason} -> {SyncResult.add_error(res, file.relative_path, reason), pmap}
    end
  end

  # Pattern-matched: files WITHOUT notion_id (creates) - ensure parent pages exist
  defp sync_single_file(
         file,
         _frontmatter,
         res,
         pmap,
         root_page_id,
         base_path,
         sync_opts,
         dry_run
       ) do
    case ensure_parent_pages(file, pmap, root_page_id, base_path, dry_run) do
      {:ok, updated_pmap, parent_id} ->
        case sync_file(file.path, parent_id, sync_opts) do
          {:ok, :created, _} ->
            {SyncResult.add_created(res, file.relative_path), updated_pmap}

          {:ok, :updated, _} ->
            {SyncResult.add_updated(res, file.relative_path), updated_pmap}

          {:ok, :skipped, _} ->
            {SyncResult.add_skipped(res, file.relative_path), updated_pmap}

          {:error, _type, reason} ->
            {SyncResult.add_error(res, file.relative_path, reason), updated_pmap}
        end

      {:error, _type, reason} ->
        {SyncResult.add_error(res, file.relative_path, reason), pmap}
    end
  end

  defp ensure_parent_pages(
         %FileEntry{parent_path: nil},
         page_map,
         root_page_id,
         _base_path,
         _dry_run
       ) do
    {:ok, page_map, root_page_id}
  end

  defp ensure_parent_pages(
         %FileEntry{parent_path: parent_path},
         page_map,
         root_page_id,
         base_path,
         dry_run
       ) do
    if Map.has_key?(page_map, parent_path) do
      {:ok, page_map, Map.get(page_map, parent_path)}
    else
      # Need to create directory pages
      create_directory_pages(parent_path, page_map, root_page_id, base_path, dry_run)
    end
  end

  defp create_directory_pages(dir_path, page_map, root_page_id, _base_path, dry_run) do
    parts = Path.split(dir_path)

    result =
      Enum.reduce_while(
        parts,
        {:ok, page_map, root_page_id, ""},
        fn part, {:ok, pmap, parent_id, current_path} ->
          new_path = if current_path == "", do: part, else: Path.join(current_path, part)

          if Map.has_key?(pmap, new_path) do
            {:cont, {:ok, pmap, Map.get(pmap, new_path), new_path}}
          else
            # Create directory page
            dir_title = humanize_dirname(part)

            case create_directory_page(parent_id, dir_title, dry_run) do
              {:ok, page_id} ->
                new_map = Map.put(pmap, new_path, page_id)
                {:cont, {:ok, new_map, page_id, new_path}}

              {:error, type, reason} ->
                {:halt, {:error, type, "Failed to create directory '#{new_path}': #{reason}"}}
            end
          end
        end
      )

    case result do
      {:ok, pmap, page_id, _path} -> {:ok, pmap, page_id}
      {:error, type, reason} -> {:error, type, reason}
    end
  end

  defp create_directory_page(_parent_id, _title, true = _dry_run) do
    {:ok, "dry-run-#{:erlang.unique_integer([:positive])}"}
  end

  defp create_directory_page(parent_id, title, false = _dry_run) do
    case Client.create_page(parent_id, title, []) do
      {:ok, response} -> {:ok, response.id}
      {:error, type, reason} -> {:error, type, reason}
    end
  end

  defp create_new_page(file_path, parent_page_id, title, blocks, body) do
    case Client.create_page(parent_page_id, title, blocks) do
      {:ok, response} ->
        # Update frontmatter with notion_id and content hash
        Frontmatter.set_notion_id(file_path, response.id, body)
        {:ok, :created, response.id}

      {:error, type, reason} ->
        {:error, type, reason}
    end
  end

  defp update_existing_page(file_path, notion_id, blocks, body) do
    case Client.update_page_blocks(notion_id, blocks) do
      {:ok, _} ->
        Frontmatter.update_synced_at(file_path, body)
        {:ok, :updated, notion_id}

      {:error, type, reason} ->
        {:error, type, reason}
    end
  end

  defp derive_title(file_path) do
    Frontmatter.derive_title_from_path(file_path)
  end

  defp humanize_dirname(name) do
    name
    |> String.replace(~r/[-_]/, " ")
    |> String.split()
    |> Enum.map(&String.capitalize/1)
    |> Enum.join(" ")
  end
end
