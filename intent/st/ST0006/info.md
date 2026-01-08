---
verblock: "08 Jan 2026:v0.2: matts - Implementation complete"
intent_version: 2.2.0
status: WIP
created: 20260108
completed:
---
# ST0006: Sync from Notion back into local markdown files

## Objective

Pull content from Notion pages back to local markdown files with conflict resolution and round-trip fidelity.

## Context

This is the reverse sync feature - the inverse of the existing sync command. It allows users to pull changes made in Notion back to their local markdown files.

## Related Steel Threads

- ST0001-ST0005: Core implementation (completed)
- ST0007: Fix md links with two-pass processing (pending - affects link resolution)

## Implementation Summary

### New Modules Created

| Module                                        | Purpose                               |
|-----------------------------------------------|---------------------------------------|
| `lib/arca_notionex/link_map.ex`               | Bidirectional path↔notion_id mappings |
| `lib/arca_notionex/blocks_from_notion.ex`     | Parse API JSON → NotionBlock structs  |
| `lib/arca_notionex/blocks_to_markdown.ex`     | NotionBlock → markdown conversion     |
| `lib/arca_notionex/conflict.ex`               | Conflict detection and resolution     |
| `lib/arca_notionex/pull.ex`                   | Pull orchestration                    |
| `lib/arca_notionex/commands/pull_command.ex`  | CLI command                           |
| `lib/arca_notionex/schemas/conflict_entry.ex` | Conflict tracking schema              |
| `lib/arca_notionex/schemas/pull_result.ex`    | Result tracking schema                |

### Modified Modules

| Module                                   | Changes                       |
|------------------------------------------|-------------------------------|
| `lib/arca_notionex/schemas/rich_text.ex` | Added `from_notion/1` parsing |
| `lib/arca_notionex/client.ex`            | Added `get_page_blocks/1`     |
| `lib/arca_notionex/configurator.ex`      | Registered `PullCommand`      |

### CLI Usage

```bash
# Basic pull (linked files only)
notionex pull --dir ./docs --root-page abc123

# Pull all child pages
notionex pull --dir ./docs --root-page abc123 --scope all-children

# With conflict resolution
notionex pull --dir ./docs --root-page abc123 --conflict notion-wins

# Dry run
notionex pull --dir ./docs --root-page abc123 --dry-run
```

### Features

- **Scope options**: `--scope linked-only`, `--scope all-children`, `--scope list`
- **Conflict resolution**: `--conflict manual`, `--conflict local-wins`, `--conflict notion-wins`, `--conflict newest-wins`
- **Dry run**: `--dry-run` shows what would happen without writing files
- **Fidelity**: Notion-specific formatting preserved in HTML comments

### Tests

- 111 total tests passing
- Unit tests for all new modules
- Round-trip tests for block parsing and markdown conversion

## Remaining Work

- Integration testing with live Notion API
- ST0007 integration for proper link resolution
