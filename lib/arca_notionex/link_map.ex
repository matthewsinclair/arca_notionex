defmodule ArcaNotionex.LinkMap do
  @moduledoc """
  Builds bidirectional mappings between relative markdown paths and Notion page IDs.

  Used by:
  - ST0007 (forward sync): path → notion_id for converting `[link](file.md)` → Notion URL
  - ST0006 (reverse sync): notion_id → path for converting Notion URL → `[link](file.md)`

  ## Example

      # Build the map from a directory
      {:ok, link_map} = LinkMap.build("/path/to/docs")

      # Forward lookup (for sync --relink)
      LinkMap.path_to_notion_id(link_map, "architecture/overview.md")
      #=> "abc123-def456"

      # Reverse lookup (for pull)
      LinkMap.notion_id_to_path(link_map, "abc123-def456")
      #=> "architecture/overview.md"

  """

  alias ArcaNotionex.Frontmatter

  @type t :: %{
          path_to_id: %{String.t() => String.t()},
          id_to_path: %{String.t() => String.t()}
        }

  @doc """
  Builds a bidirectional link map from all markdown files in a directory.

  Scans all .md files recursively, reads their frontmatter, and builds
  mappings between relative paths and notion_ids.
  """
  @spec build(String.t()) :: {:ok, t()} | {:error, atom(), String.t()}
  def build(dir) do
    if File.dir?(dir) do
      path_to_id =
        dir
        |> find_markdown_files()
        |> Enum.map(&extract_mapping(&1, dir))
        |> Enum.reject(&is_nil/1)
        |> Map.new()

      id_to_path = Map.new(path_to_id, fn {path, id} -> {id, path} end)

      {:ok, %{path_to_id: path_to_id, id_to_path: id_to_path}}
    else
      {:error, :not_found, "Directory not found: #{dir}"}
    end
  end

  @doc """
  Returns an empty link map.
  """
  @spec empty() :: t()
  def empty do
    %{path_to_id: %{}, id_to_path: %{}}
  end

  @doc """
  Looks up the Notion page ID for a given relative path.

  Used by forward sync (--relink) to resolve internal markdown links.
  """
  @spec path_to_notion_id(t(), String.t()) :: String.t() | nil
  def path_to_notion_id(%{path_to_id: map}, path) do
    normalized = normalize_path(path)
    Map.get(map, normalized)
  end

  @doc """
  Looks up the relative path for a given Notion page ID.

  Used by reverse sync (pull) to resolve Notion URLs back to markdown paths.
  """
  @spec notion_id_to_path(t(), String.t()) :: String.t() | nil
  def notion_id_to_path(%{id_to_path: map}, notion_id) do
    # Strip any URL prefix to get just the ID
    id = extract_notion_id(notion_id)
    Map.get(map, id)
  end

  @doc """
  Resolves a link href using the link map.

  For forward sync (local → Notion):
  - Internal .md links → Notion URLs
  - External links → unchanged

  ## Options
  - `:direction` - :forward (path→notion) or :reverse (notion→path)
  - `:current_file` - current file path for resolving relative links
  """
  @spec resolve_link(t(), String.t(), keyword()) :: String.t()
  def resolve_link(link_map, href, opts \\ []) do
    direction = Keyword.get(opts, :direction, :forward)
    current_file = Keyword.get(opts, :current_file)

    case direction do
      :forward -> resolve_forward(link_map, href, current_file)
      :reverse -> resolve_reverse(link_map, href)
    end
  end

  # Forward resolution: path → Notion URL
  defp resolve_forward(link_map, href, current_file) do
    cond do
      # External link - keep as-is
      String.starts_with?(href, "http://") or String.starts_with?(href, "https://") ->
        href

      # Anchor only - keep as-is
      String.starts_with?(href, "#") ->
        href

      # Internal .md link - try to resolve
      String.ends_with?(href, ".md") or String.contains?(href, ".md#") ->
        {path, anchor} = split_anchor(href)
        resolved_path = resolve_relative_path(path, current_file)

        case path_to_notion_id(link_map, resolved_path) do
          nil ->
            href

          notion_id ->
            base_url = "https://notion.so/#{notion_id}"
            if anchor, do: "#{base_url}##{anchor}", else: base_url
        end

      # Other - keep as-is
      true ->
        href
    end
  end

  # Reverse resolution: Notion URL → path
  defp resolve_reverse(link_map, href) do
    cond do
      # Notion URL - resolve to local path
      is_notion_url?(href) ->
        {notion_id, anchor} = extract_notion_id_and_anchor(href)

        case notion_id_to_path(link_map, notion_id) do
          nil ->
            href

          path ->
            if anchor, do: "#{path}##{anchor}", else: path
        end

      # Not a Notion URL - keep as-is
      true ->
        href
    end
  end

  # Private helpers

  defp find_markdown_files(dir) do
    Path.wildcard(Path.join(dir, "**/*.md"))
  end

  defp extract_mapping(file_path, base_dir) do
    with {:ok, content} <- File.read(file_path),
         {:ok, frontmatter, _body} <- Frontmatter.parse(content),
         notion_id when is_binary(notion_id) <- Map.get(frontmatter, :notion_id) do
      relative_path = Path.relative_to(file_path, base_dir)
      {relative_path, notion_id}
    else
      _ -> nil
    end
  end

  defp normalize_path(path) do
    path
    |> String.trim_leading("./")
    |> String.downcase()
  end

  defp split_anchor(href) do
    case String.split(href, "#", parts: 2) do
      [path, anchor] -> {path, anchor}
      [path] -> {path, nil}
    end
  end

  defp resolve_relative_path(path, nil), do: normalize_path(path)

  defp resolve_relative_path(path, current_file) do
    current_dir = Path.dirname(current_file)
    Path.join(current_dir, path) |> Path.expand() |> normalize_path()
  end

  defp is_notion_url?(url) do
    String.starts_with?(url, "https://notion.so/") or
      String.starts_with?(url, "https://www.notion.so/")
  end

  defp extract_notion_id(url_or_id) do
    url_or_id
    |> String.replace(~r{^https://(www\.)?notion\.so/}, "")
    |> String.split("#")
    |> hd()
    |> String.split("?")
    |> hd()
  end

  defp extract_notion_id_and_anchor(url) do
    id = extract_notion_id(url)

    anchor =
      case String.split(url, "#", parts: 2) do
        [_, anchor] -> anchor
        _ -> nil
      end

    {id, anchor}
  end
end
