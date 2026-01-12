---
title: Image Support
status: DONE
priority: high
---
# WP01: Image Support

## Summary

Add support for converting markdown images to Notion image blocks.

## Problem

Markdown images (`![alt](url)`) fall through to the catch-all in `ast_to_blocks.ex:173-176` and are silently dropped. EarmarkParser produces `{"img", [{"src", "url"}, {"alt", "text"}], [], %{}}` but no handler exists.

## Solution

1. Add `:image` to NotionBlock schema (`@block_types`, type spec, embedded field)
2. Add `image/2` constructor to NotionBlock
3. Add `to_notion/1` clause for image blocks
4. Add `convert_node` handler for `img` tags in `ast_to_blocks.ex`

## Files to Modify

- `lib/arca_notionex/schemas/notion_block.ex` - Add image type, field, constructor, to_notion
- `lib/arca_notionex/ast_to_blocks.ex` - Add convert_node for img tags
- `test/arca_notionex/ast_to_blocks_test.exs` - Add image conversion tests

## Edge Cases

| Input                         | Behavior               |
|-------------------------------|------------------------|
| `https://...` or `http://...` | Convert to image block |
| `./img.png` (relative)        | Skip with warning      |
| `data:image/...`              | Skip with warning      |
| Missing/empty src             | Skip silently          |
| Alt text                      | Used as caption        |

## Acceptance Criteria

- [x] External URL images convert to Notion image blocks
- [x] Alt text becomes image caption
- [x] Relative paths skipped silently (no warning to reduce noise)
- [x] Data URLs skipped silently (no warning to reduce noise)
- [x] Tests pass for all edge cases (8 new tests added)
