---
intent_version: 2.2.0
status: TODO
created: 20260112
completed:
---
# ST0009: Image Support & Incremental Sync

## Summary

Two related issues in the sync pipeline:

1. **Images are silently dropped** - Markdown images (`![alt](url)`) are not converted to Notion blocks
2. **Incremental sync not implemented** - All files re-sync every time despite `content_hash` infrastructure

---

## Issue 1: Images Silently Dropped

### Current Behavior

Markdown images are parsed by EarmarkParser but silently discarded:

```markdown
## Screenshots

![Dashboard](./dashboard.png)
![Login Flow](https://example.com/login.png)
```

Result in Notion: Empty section, no images, no warnings.

### Root Cause

`lib/arca_notionex/ast_to_blocks.ex` has no handler for `img` tags:

```elixir
# Line 173 - catch-all silently drops unknown nodes
def convert_node(_unknown, _opts) do
  # Skip unsupported nodes
  []
end
```

EarmarkParser produces: `{"img", [{"src", "url"}, {"alt", "text"}], [], %{}}`

This falls through to the catch-all and returns `[]`.

### Expected Behavior

Images should convert to Notion image blocks. Notion API supports:

```json
{
  "type": "image",
  "image": {
    "type": "external",
    "external": {
      "url": "https://example.com/image.png"
    }
  }
}
```

### Proposed Fix

Add image handler in `ast_to_blocks.ex`:

```elixir
def convert_node({"img", attrs, _, _}, _opts) do
  src = get_attr(attrs, "src")
  alt = get_attr(attrs, "alt") || ""

  cond do
    is_nil(src) or src == "" ->
      []

    String.starts_with?(src, ["http://", "https://"]) ->
      # External URL - create image block
      [NotionBlock.image(src, alt)]

    true ->
      # Local/relative path - skip with warning
      IO.warn("Skipping local image (Notion requires URLs): #{src}")
      []
  end
end
```

And add to `NotionBlock` schema:

```elixir
def image(url, caption \\ "") do
  %__MODULE__{
    type: "image",
    image: %{
      type: "external",
      external: %{url: url},
      caption: if(caption != "", do: [RichText.text(caption)], else: [])
    }
  }
end
```

### Edge Cases to Consider

| Case | Handling |
|------|----------|
| External URLs (`https://...`) | Convert to image block |
| Relative paths (`./img.png`) | Skip with warning (or support `--base-url` option) |
| Data URLs (`data:image/...`) | Skip (too large, not supported by Notion) |
| Missing src attribute | Skip silently |
| Alt text with special chars | Pass through to caption |

### Optional Enhancement

Add `--base-url` option to convert relative paths:

```bash
notionex sync --dir ./docs --root-page abc123 --base-url https://raw.githubusercontent.com/org/repo/main/docs
```

This would transform `![](./img.png)` to `https://raw.githubusercontent.com/org/repo/main/docs/img.png`

---

## Issue 2: Incremental Sync Not Implemented

### Current Behavior

Every file with a `notion_id` is re-synced on every run:

```
$ bin/notionex sync a3-product --relink

Pass 1/2: Creating pages (2 new files)
Pass 2/2: Resolving links
Sync Complete
=============
Created: 2
Updated: 16  # <-- ALL 16 existing files re-synced
Skipped: 0   # <-- Never skips anything
Errors:  0
```

Even unchanged files make API calls, wasting:

- API rate limit quota
- Time (each update is ~500ms)
- Notion version history (cluttered with identical updates)

### Root Cause

The `content_hash` infrastructure exists but is never used:

**Frontmatter stores hash** (`frontmatter.ex:110`):

```elixir
def set_notion_id(file_path, notion_id, body \\ nil) do
  updates = %{notion_id: notion_id, notion_synced_at: DateTime.utc_now()}
  updates = case body do
    nil -> updates
    content -> Map.put(updates, :content_hash, compute_hash(content))
  end
  update_file(file_path, updates)
end
```

**Hash comparison exists** (`frontmatter.ex:166-170`):

```elixir
def content_changed?(_current_content, nil), do: true
def content_changed?(current_content, stored_hash) do
  compute_hash(current_content) != stored_hash
end
```

**But sync never checks it** (`sync.ex:163-165`):

```elixir
# Updates unconditionally - no hash check
defp sync_action(file_path, _parent_id, _title, blocks, body, %{notion_id: notion_id}, false)
     when is_binary(notion_id) do
  update_existing_page(file_path, notion_id, blocks, body)
end
```

### Expected Behavior

```
$ bin/notionex sync a3-product --relink

Sync Complete
=============
Created: 0
Updated: 2   # <-- Only changed files
Skipped: 16  # <-- Unchanged files skipped
Errors:  0
```

### Proposed Fix

Modify `sync_action` for existing pages in `sync.ex`:

```elixir
# Live mode: existing page (has notion_id) - check if changed first
defp sync_action(file_path, _parent_id, _title, blocks, body, %{notion_id: notion_id, content_hash: stored_hash}, false)
     when is_binary(notion_id) do
  if Frontmatter.content_changed?(body, stored_hash) do
    update_existing_page(file_path, notion_id, blocks, body)
  else
    {:ok, :skipped, notion_id}
  end
end
```

### Considerations

1. **First sync after this change**: Files synced before hash storage will have `content_hash: nil`, so `content_changed?(_, nil)` returns `true` - they'll sync once to populate the hash.

2. **Link resolution**: When `--relink` resolves `.md` links to Notion URLs, the *rendered blocks* change but the *source markdown body* doesn't. The hash is computed on `body` (source), so link-only changes won't trigger re-sync. This is correct because:
   - Links are resolved at render time
   - Source file hasn't changed
   - Re-running `--relink` will re-resolve links anyway

3. **Force sync option**: Consider adding `--force` flag to bypass hash check when needed:

   ```bash
   notionex sync --dir ./docs --root-page abc123 --force
   ```

### Performance Impact

For a 50-file doc set where 2 files changed:

| Metric | Before | After |
|--------|--------|-------|
| API calls | 50 | 2 |
| Time | ~25s | ~1s |
| Rate limit impact | High | Minimal |

---

## Files to Modify

| File | Changes |
|------|---------|
| `lib/arca_notionex/ast_to_blocks.ex` | Add `convert_node` for `img` tags |
| `lib/arca_notionex/schemas/notion_block.ex` | Add `image/2` constructor |
| `lib/arca_notionex/sync.ex` | Check `content_changed?` before update |
| `test/arca_notionex/ast_to_blocks_test.exs` | Add image conversion tests |
| `test/arca_notionex/sync_test.exs` | Add incremental sync tests |

---

## Test Cases

### Image Support

```elixir
test "converts external image to notion block" do
  md = "![Alt text](https://example.com/img.png)"
  {:ok, [[block]]} = AstToBlocks.convert(md)
  assert block.type == "image"
  assert block.image.external.url == "https://example.com/img.png"
end

test "skips relative image paths with warning" do
  md = "![Local](./local.png)"
  {:ok, [blocks]} = AstToBlocks.convert(md)
  assert blocks == []
end
```

### Incremental Sync

```elixir
test "skips unchanged files" do
  # Setup: file with matching hash
  # Action: sync
  # Assert: returns :skipped, no API call made
end

test "updates changed files" do
  # Setup: file with different hash
  # Action: sync
  # Assert: returns :updated, API call made, hash updated
end

test "syncs files without stored hash" do
  # Setup: file with notion_id but no content_hash
  # Action: sync
  # Assert: returns :updated, hash now stored
end
```

---

## Priority

**High** - Both issues affect daily workflow:

- Images are common in documentation
- Full re-sync on every run is wasteful and slow
