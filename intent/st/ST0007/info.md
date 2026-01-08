---
verblock: "08 Jan 2026:v0.2: matts - Implementation complete"
intent_version: 2.2.0
status: WIP
created: 20260108
completed:
---
# ST0007: Fix md links in Notion with two-pass processing

## Objective

Resolve internal markdown links to Notion page URLs during sync.

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

## Solution: Two-Pass Sync with `--relink`

### CLI Usage

```bash
# First sync: creates pages (links will be broken)
notionex sync --dir ./docs --root-page abc123

# Second sync with relink: resolves internal links
notionex sync --dir ./docs --root-page abc123 --relink
```

## Implementation Summary

### Modules Modified

| Module                                       | Changes                                                     |
|----------------------------------------------|-------------------------------------------------------------|
| `lib/arca_notionex/link_map.ex`              | Shared module for ST0006+ST0007 (already created in ST0006) |
| `lib/arca_notionex/ast_to_blocks.ex`         | Added `link_map` and `current_file` options                 |
| `lib/arca_notionex/commands/sync_command.ex` | Added `--relink` flag                                       |
| `lib/arca_notionex/sync.ex`                  | Build and pass LinkMap when relink=true                     |
| `scripts/completions/completions.txt`        | Added `--relink`                                            |

### Key Changes

1. **AstToBlocks.convert/2** now accepts options:
   - `:link_map` - LinkMap for resolving internal .md links
   - `:current_file` - Current file path for resolving relative links

2. **Link Resolution Flow:**

   ```
   [link](other.md)
   → resolve_link() checks if .md file
   → looks up in LinkMap.path_to_notion_id()
   → returns https://notion.so/<notion_id>
   ```

3. **Sync Module:**
   - When `--relink` is passed, builds LinkMap from directory
   - Passes `link_map` and `current_file` to AstToBlocks.convert

### Features

- **Case-insensitive matching**: `OVERVIEW.MD` resolves to `overview.md`
- **Relative path support**: `../other.md` resolved from current file location
- **Anchor preservation**: `file.md#section` → `https://notion.so/id#section`
- **External link preservation**: HTTP/HTTPS links unchanged
- **Bidirectional**: Same LinkMap module used by ST0006 for reverse resolution

### Relationship with ST0006

Both ST0006 (pull) and ST0007 (sync --relink) share the `LinkMap` module:

| Direction        | Usage                                            |
|------------------|--------------------------------------------------|
| Forward (ST0007) | path → notion_id: `[link](file.md)` → Notion URL |
| Reverse (ST0006) | notion_id → path: Notion URL → `[link](file.md)` |

### Tests

- 27 new tests in `link_map_test.exs`
- 10 new tests in `ast_to_blocks_test.exs` (link resolution describe block)
- 7 new tests in `blocks_to_markdown_test.exs` (reverse resolution)
- Total: 145 tests passing

## Workflow

```bash
# 1. First sync - creates pages, populates notion_ids in frontmatter
notionex sync --dir ./docs --root-page abc123

# 2. Second sync with relink - resolves internal links
notionex sync --dir ./docs --root-page abc123 --relink
```
