---
verblock: "12 Jan 2026:v0.2: matts - Completed with as-built"
intent_version: 2.2.0
status: DONE
created: 20260112
completed: 20260112
---
# ST0011: Link resolution and duplicate subpage handling

## Objective

Fix link handling issues in notionex sync where internal links weren't resolving to page mentions and `skip_child_links` was incorrectly auto-enabled.

## As-Built Summary

### Issue 1: Link Resolution - VERIFIED WORKING

Link resolution was verified working through comprehensive tests. Added 18 new tests covering:
- Nested directory structures (`prototypes/storyfield/index.md`)
- Relative path resolution (`../root.md` from `docs/child.md`)
- Anchor handling (`overview.md#section`)
- External URL preservation

### Issue 2 & 3: skip_child_links - FIXED (Made Opt-In)

The original implementation auto-enabled `skip_child_links` with `--relink`, which incorrectly stripped links based on filesystem structure rather than Notion hierarchy.

**Solution implemented**: Option A - Made `skip_child_links` opt-in via explicit `--skip-child-links` flag.

| Before (broken) | After (fixed) |
|-----------------|---------------|
| `--relink` auto-enables skip_child_links | `--relink` preserves all links |
| No way to disable | `--skip-child-links` flag to opt-in |
| Peer pages incorrectly stripped | Safe default behavior |

## Files Modified

| File | Changes |
|------|---------|
| `lib/arca_notionex/commands/sync_command.ex` | Added `--skip-child-links` flag |
| `lib/arca_notionex/sync.ex` | Removed hardcoded `skip_child_links: true`, now uses flag value |
| `lib/arca_notionex/link_map.ex` | Added `is_child_link?/2` function |
| `lib/arca_notionex/ast_to_blocks.ex` | Added `skip_child_links` option handling |
| `test/arca_notionex/link_map_test.exs` | Added 11 tests for `is_child_link?` |
| `test/arca_notionex/ast_to_blocks_test.exs` | Added 7 tests for link resolution and skip_child_links |

## Usage

```bash
# Default: --relink preserves all links as page mentions
notionex sync --dir ./docs --root-page abc123 --relink

# Opt-in: Skip links to subdirectories (when they are true Notion children)
notionex sync --dir ./docs --root-page abc123 --relink --skip-child-links
```

## Tests

- Total: 222 tests, 0 failures
- Version: 0.1.12
