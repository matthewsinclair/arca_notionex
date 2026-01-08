---
verblock: "08 Jan 2026:v0.1: matts - Initial version"
intent_version: 2.2.0
status: WIP
created: 20260108
completed:
---
# ST0007: Fix md links in Notion with two-pass processing

## Problem

When syncing markdown files to Notion, internal links between documents are broken.

**Example:**

```markdown
See [System Overview](system-overview.md) for details.
```

**Current behavior:**

- Link becomes `https://www.notion.so/system-overview.md` (broken)

**Expected behavior:**

- Link becomes `https://www.notion.so/abc123...` (actual Notion page ID)

## Root Cause

Chicken-and-egg problem:

1. First sync creates pages and stores `notion_id` in each file's frontmatter
2. But during that first sync, we don't know sibling pages' IDs yet
3. Links are converted literally, resulting in broken `.md` URLs

## Proposed Solution: Two-Pass Sync with `--relink`

### Usage

```bash
# First sync: creates pages (links will be broken)
notionex sync --dir ./docs --root-page abc123

# Second sync with relink: resolves internal links
notionex sync --dir ./docs --root-page abc123 --relink
```

## Implementation

### 1. Build Link Map (new module)

```elixir
defmodule ArcaNotionex.LinkMap do
  @doc """
  Builds a map of relative markdown paths to Notion page IDs
  by reading frontmatter from all files in the directory.
  """
  def build(dir) do
    dir
    |> find_markdown_files()
    |> Enum.map(&extract_mapping(&1, dir))
    |> Enum.reject(&is_nil/1)
    |> Map.new()
  end

  defp find_markdown_files(dir) do
    Path.wildcard(Path.join(dir, "**/*.md"))
  end

  defp extract_mapping(file_path, base_dir) do
    with {:ok, content} <- File.read(file_path),
         {:ok, %{frontmatter: %{"notion_id" => notion_id}}} <- Frontmatter.parse(content) do
      relative_path = Path.relative_to(file_path, base_dir)
      {relative_path, notion_id}
    else
      _ -> nil
    end
  end
end
```

**Example output:**

```elixir
%{
  "index.md" => "abc123-def456",
  "architecture/system-overview.md" => "789xyz-...",
  "architecture/data-storage.md" => "..."
}
```

### 2. Modify AstToBlocks to Accept Link Map

```elixir
defmodule ArcaNotionex.AstToBlocks do
  # Add link_map as optional parameter (default empty map)
  def convert(ast, opts \\ []) do
    link_map = Keyword.get(opts, :link_map, %{})
    convert_nodes(ast, link_map)
  end

  # When converting a link node
  defp convert_link(href, text, link_map) do
    resolved_href = resolve_link(href, link_map)
    # ... create Notion link block with resolved_href
  end

  defp resolve_link(href, link_map) do
    cond do
      # External link - keep as-is
      String.starts_with?(href, "http") ->
        href

      # Internal .md link - try to resolve
      String.ends_with?(href, ".md") ->
        case Map.get(link_map, normalize_path(href)) do
          nil -> href  # Not found, keep original (will be broken)
          notion_id -> "https://notion.so/#{notion_id}"
        end

      # Anchor or other - keep as-is
      true ->
        href
    end
  end

  # Handle relative paths: "./foo.md", "../bar.md", "foo.md"
  defp normalize_path(href) do
    href
    |> String.trim_leading("./")
    # May need more sophisticated path resolution for "../" references
  end
end
```

### 3. Modify Sync to Support `--relink`

```elixir
def sync(dir, root_page_id, opts \\ []) do
  relink? = Keyword.get(opts, :relink, false)

  link_map = if relink? do
    LinkMap.build(dir)
  else
    %{}
  end

  # Pass link_map to the conversion pipeline
  files
  |> Enum.each(fn file ->
    content = File.read!(file)
    {frontmatter, markdown} = Frontmatter.parse(content)
    ast = EarmarkParser.as_ast!(markdown)
    blocks = AstToBlocks.convert(ast, link_map: link_map)
    # ... sync to Notion
  end)
end
```

### 4. Add CLI Flag

In `NotionexSyncCommand`:

```elixir
config :"notionex.sync",
  # ... existing config ...
  flags: [
    relink: [short: "-r", long: "--relink", help: "Resolve internal .md links to Notion pages"]
  ]
```

## Edge Cases to Handle

1. **Relative paths with `../`**
   - `[Ops](../operations/index.md)` from `architecture/index.md`
   - Need to resolve relative to current file's location

2. **Anchor links**
   - `[Section](#section-name)` - keep as-is (Notion handles these)
   - `[Other Page](other.md#section)` - resolve page, keep anchor

3. **Missing targets**
   - Link to file that doesn't exist or wasn't synced
   - Options: keep broken link, remove link (keep text), log warning

4. **Case sensitivity**
   - `System-Overview.md` vs `system-overview.md`
   - Normalize to lowercase for matching?

## Testing

```elixir
# test/link_map_test.exs
test "builds link map from frontmatter" do
  # Create temp files with frontmatter
  # Verify map is built correctly
end

# test/ast_to_blocks_test.exs
test "resolves internal .md links" do
  link_map = %{"other.md" => "notion-id-123"}
  ast = [{"a", [{"href", "other.md"}], ["Other Page"], %{}}]

  blocks = AstToBlocks.convert(ast, link_map: link_map)

  # Assert link URL is https://notion.so/notion-id-123
end

test "preserves external links" do
  ast = [{"a", [{"href", "https://example.com"}], ["Example"], %{}}]
  blocks = AstToBlocks.convert(ast, link_map: %{})

  # Assert link URL is unchanged
end
```

## Workflow After Implementation

```bash
# 1. Prepare files (add frontmatter)
notionex prepare --dir ./a3-engineering

# 2. First sync (creates pages, links broken)
notionex sync --dir ./a3-engineering --root-page abc123

# 3. Second sync with relink (fixes links)
notionex sync --dir ./a3-engineering --root-page abc123 --relink

# Or combine into single command with auto-relink:
notionex sync --dir ./a3-engineering --root-page abc123 --auto-relink
# (Does two passes internally)
```

## Priority

**High** - Without this, internal documentation links are all broken, significantly reducing the usefulness of the Notion sync.
