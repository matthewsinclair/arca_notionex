---
verblock: "12 Jan 2026:v0.1: matts - Initial version"
---
# Session Restart Context

## Project: arca_notionex

Elixir CLI tool for bidirectional markdown <-> Notion sync.

**Version:** 0.1.12
**Tests:** 222 passing

## Quick Start

```bash
# Run tests
mix test

# Build CLI
mix escript.build

# Install globally
mix escript.install --force

# Check version
notionex --version
```

## Current State

All steel threads complete. No active WIP.

## Recent Work (v0.1.10 - v0.1.12)

- **v0.1.12**: Fixed `skip_child_links` bug - now opt-in via `--skip-child-links` flag
- **v0.1.11**: index.md populates parent directory page
- **v0.1.10**: Image support + incremental sync

## Key Architecture

| Component | File | Purpose |
|-----------|------|---------|
| CLI Entry | `lib/arca_notionex/cli.ex` | Command dispatch |
| Sync Command | `lib/arca_notionex/commands/sync_command.ex` | Markdown -> Notion |
| Block Conversion | `lib/arca_notionex/ast_to_blocks.ex` | MD AST -> Notion blocks |
| Link Resolution | `lib/arca_notionex/link_map.ex` | .md links -> page mentions |
| Frontmatter | `lib/arca_notionex/frontmatter.ex` | YAML parsing, notion_id tracking |
| Notion API | `lib/arca_notionex/client.ex` | API wrapper |

## Documentation

- `CLAUDE.md` - Project guidelines
- `CHANGELOG.md` - Version history
- `intent/wip.md` - Work in progress status
- `intent/st/COMPLETED/` - Completed steel threads
- `intent/st/steel_threads.md` - Steel thread index

## Common Tasks

```bash
# New steel thread
intent st new "Feature title"

# List steel threads
intent st list

# Mark complete
intent st done <id>

# Full test suite
mix test --seed 0
```

## Potential Future Work

See `intent/wip.md` for ideas.
