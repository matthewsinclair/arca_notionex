---
st_id: ST0008
title: Critical Bug Fixes - Directory Hierarchy & Title Management
status: Completed
created: 2026-01-08
completed: 2026-01-08
---

# ST0008: Critical Bug Fixes - Directory Hierarchy & Title Management

## Objective

Fix critical bugs discovered during production sync testing that prevent proper bidirectional sync between local markdown files and Notion pages.

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

## Issues Addressed

| Issue                    | Priority | Summary                                                       |
|--------------------------|----------|---------------------------------------------------------------|
| Directory Flattening     | P0       | All pages created flat under root instead of nested hierarchy |
| Duplicate "Index" Titles | P0       | Multiple index.md files all titled "Index"                    |
| Incremental Sync         | P1       | No change detection - syncs all files every time              |
| Formatting Preservation  | P2       | Verify Notion-specific formatting round-trips                 |

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
- [x] Two-pass `--relink` automatically handles new files
- [x] Pattern-matched code style (no `case true/false`)
- [x] Single file read per sync (eliminated double read)
- [x] Audit table uses proper Ctx flow with Owl rendering
- [x] GitHub Actions CI for automated testing
- [x] `--version` / `-v` flags work correctly
- [x] MIT License for open source distribution
- [x] All tests pass (187 tests, 0 failures)

### Deferred to Future Work

- [ ] `--force` syncs all files regardless of changes
- [ ] `--local-wins` / `--notion-wins` conflict resolution flags
- [ ] Skip unchanged files based on hash comparison

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

## Acceptance

Acceptance Criteria and Acceptance Tests are RENDERED into `acceptance.md`, which is a GENERATED VIEW -- a row authored there is discarded by the next sync. The contract is canon in this thread's model: change a state with the `intent ac` / `intent at` verbs, and mint or reword a row in `.canon/st/ST0008.json`, then `intent sync --to-store`. This cover never restates them.

---

_Generated by Intent v3.0.0 from `thread.json`. Do not edit this file -- it is rendered from the model, and `intent doctor` reports any hand-edit as skew._
