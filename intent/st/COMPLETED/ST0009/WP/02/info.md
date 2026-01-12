---
title: Incremental Sync
status: DONE
priority: high
---
# WP02: Incremental Sync

## Summary

Implement incremental sync using the existing (but unused) content_hash infrastructure to skip unchanged files.

## Problem

`sync.ex:163-166` unconditionally updates all files with `notion_id`. The `content_changed?/2` function exists in `frontmatter.ex` but is never called.

Current behavior:

```
$ bin/notionex sync a3-product --relink
Updated: 16  # ALL 16 existing files re-synced
Skipped: 0   # Never skips anything
```

This wastes API rate limits, time (~500ms per file), and clutters Notion version history.

## Solution

Modify `sync_action` to check `content_changed?` before updating:

```elixir
defp sync_action(file_path, _parent_id, _title, blocks, body,
                 %{notion_id: notion_id, content_hash: stored_hash}, false)
     when is_binary(notion_id) do
  if Frontmatter.content_changed?(body, stored_hash) do
    update_existing_page(file_path, notion_id, blocks, body)
  else
    {:ok, :skipped, notion_id}
  end
end
```

## Files to Modify

- `lib/arca_notionex/sync.ex` - Check content_changed? before update
- `test/arca_notionex/sync_test.exs` - Add incremental sync tests

## Edge Cases

| Scenario                                   | Behavior                                              |
|--------------------------------------------|-------------------------------------------------------|
| `stored_hash` is `nil` (legacy/first sync) | `content_changed?(_, nil)` returns `true`, file syncs |
| Content unchanged                          | Returns `{:ok, :skipped, notion_id}`                  |
| Content changed                            | Updates and stores new hash                           |

## Performance Impact

For 50-file doc set with 2 changed:

- API calls: 50 -> 2
- Time: ~25s -> ~1s
- Rate limit impact: High -> Minimal

## Acceptance Criteria

- [x] Unchanged files are skipped
- [x] Changed files are updated and hash stored
- [x] Files with nil hash sync and get hash populated
- [x] Sync summary shows correct "Skipped" count
- [x] Tests pass for all scenarios (2 new tests added)
