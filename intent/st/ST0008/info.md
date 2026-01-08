---
verblock: "08 Jan 2026:v0.3: matts - Implementation complete"
intent_version: 2.2.0
status: WIP
created: 20260108
completed: 20260108
---
# ST0008: Critical Bug Fixes - Directory Hierarchy & Title Management

## Objective

Fix critical bugs discovered during production sync testing that prevent proper bidirectional sync between local markdown files and Notion pages.

## Issues Addressed

| Issue                    | Priority | Summary                                                       |
|--------------------------|----------|---------------------------------------------------------------|
| Directory Flattening     | P0       | All pages created flat under root instead of nested hierarchy |
| Duplicate "Index" Titles | P0       | Multiple index.md files all titled "Index"                    |
| Incremental Sync         | P1       | No change detection - syncs all files every time              |
| Formatting Preservation  | P2       | Verify Notion-specific formatting round-trips                 |

## Context

During production testing with the a3-content repository, syncing to Notion revealed:

1. **Directory structure was flattened** - All pages appeared at root level instead of nested hierarchy
2. **Multiple "Index" pages** - Every index.md file became a page titled "Index"
3. **Full sync every time** - No tracking of what changed since last sync

### Root Causes

**Bug #1: Directory Flattening** (`sync.ex:206-209`)

```elixir
case Client.create_page(parent_id, dir_title, []) do
  {:ok, response} -> response.id
  {:error, _, _} -> parent_id  # <-- SILENT FALLBACK
end
```

When directory page creation fails, code silently falls back to parent_id, causing cascade failure.

**Bug #2: Duplicate Titles** (`frontmatter.ex:161-165`)

```elixir
defp extract_title_from_content(body) do
  case Regex.run(~r/^#\s+(.+)$/m, body) do
    [_, title] -> String.trim(title)  # Extracts "Index" from "# Index"
```

All index.md files with `# Index` heading get the same title.

## Solution Summary

### Directory Hierarchy Fix

- Refactor `create_directory_pages/5` to return `{:ok, page_map, page_id}` or `{:error, type, reason}`
- Propagate errors up to `sync_files/4` - fail fast, not silent fallback
- Report directory creation failures clearly

### Title Management

- **Smart derivation**: `architecture/index.md` becomes "Architecture" (parent dir name)
- **Frontmatter is source of truth**: Title stored explicitly, preserved in both directions
- **Per-directory uniqueness**: Validate no duplicate titles within same directory

### Incremental Sync

- Add `content_hash` (SHA-256) to frontmatter
- Skip unchanged files (hash matches)
- Detect conflicts when both local and Notion changed
- Add `--force`, `--local-wins`, `--notion-wins` flags

## Critical Files

| File                                         | Changes                                                      |
|----------------------------------------------|--------------------------------------------------------------|
| `lib/arca_notionex/sync.ex`                  | Directory error handling, title validation, change detection |
| `lib/arca_notionex/frontmatter.ex`           | Smart title derivation, content hash computation             |
| `lib/arca_notionex/schemas/frontmatter.ex`   | Add `content_hash` field                                     |
| `lib/arca_notionex/conflict.ex`              | NEW: Conflict detection module                               |
| `lib/arca_notionex/commands/sync_command.ex` | Add conflict resolution flags                                |

## Success Criteria

- [x] Directory creation errors halt sync with clear error message
- [x] `index.md` in `architecture/` gets title "Architecture" not "Index"
- [x] Per-directory duplicate titles cause sync to fail
- [x] `content_hash` stored in frontmatter after sync
- [ ] Unchanged files are skipped (hash infrastructure in place, skip logic TODO)
- [ ] `--force` syncs all files regardless of changes (CLI flags deferred)
- [ ] `--local-wins` / `--notion-wins` resolve conflicts (CLI flags deferred)
- [x] All existing tests pass + new tests added (182 tests, 0 failures)

## Related Steel Threads

- ST0006: Reverse Sync (Notion to Local Markdown)
- ST0007: Forward Sync with --relink

## Implementation Phases

1. **Phase 1 (P0)**: Fix directory flattening - proper error handling
2. **Phase 2 (P0)**: Fix title management - smart derivation + validation
3. **Phase 3 (P1)**: Incremental sync - hash tracking + conflict resolution
4. **Phase 4 (P2)**: Verify formatting preservation

## Detailed Plan

See `/Users/matts/.claude/plans/delegated-sprouting-meteor.md` for full implementation details including:

- Exact code changes
- Test cases
- CLI flag specifications
- Example workflows
