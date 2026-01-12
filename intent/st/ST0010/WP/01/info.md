---
title: index.md Populates Parent Directory
status: DONE
priority: high
---
# WP01: index.md Populates Parent Directory Page

## Summary

Modified sync pipeline so that `index.md` files populate their parent directory page instead of creating a redundant child page.

## Implementation

1. Added new `sync_single_file` clause matching `%FileEntry{filename: "index.md"}` (before the generic clause)
2. This clause calls `sync_index_to_directory/4` which updates the parent directory page content
3. The directory page's notion_id is stored in the index.md frontmatter for subsequent updates

## Files Modified

- `lib/arca_notionex/sync.ex` - Added `sync_index_to_directory/4` and index.md-specific clause
- `test/arca_notionex/sync_test.exs` - Added 2 tests for index.md handling

## Acceptance Criteria

- [x] index.md content populates directory page (not child)
- [x] Directory page notion_id stored in index.md frontmatter
- [x] Other files in same directory still create as children
- [x] Tests pass
