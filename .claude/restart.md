# Claude Code Session Restart

## Project: arca_notionex

Elixir CLI for bidirectional markdown <-> Notion synchronization.

**Version:** 0.1.12 | **Tests:** 222 passing

## WIP Status

**No active work** - All steel threads complete.

Check `intent/wip.md` for current state.

## TODO / Future Work

Potential enhancements (not yet started):

- `--base-url` option to convert relative image paths to full URLs
- `--force` flag to bypass content hash check
- Table of contents generation
- Notion-to-markdown fidelity improvements

## Quick Reference

```bash
mix test                    # Run tests
mix escript.build           # Build CLI
mix escript.install --force # Install globally
notionex --version          # Verify installation
```

## Starting New Work

```bash
intent st new "Feature or bug title"  # Create steel thread
intent st list                        # List all threads
intent st done <id>                   # Mark complete
```

## Key Documentation

| Document | Path | Purpose |
|----------|------|---------|
| Project Guidelines | `CLAUDE.md` | Coding standards, patterns |
| Changelog | `CHANGELOG.md` | Version history |
| WIP Status | `intent/wip.md` | Current work status |
| Steel Threads | `intent/st/COMPLETED/` | Completed work docs |
| Session Context | `intent/restart.md` | Restart context |

## Key Code Files

| Component | Path |
|-----------|------|
| CLI Entry | `lib/arca_notionex/cli.ex` |
| Sync Command | `lib/arca_notionex/commands/sync_command.ex` |
| Sync Logic | `lib/arca_notionex/sync.ex` |
| Block Conversion | `lib/arca_notionex/ast_to_blocks.ex` |
| Link Resolution | `lib/arca_notionex/link_map.ex` |
| Frontmatter | `lib/arca_notionex/frontmatter.ex` |
| Notion API | `lib/arca_notionex/client.ex` |

## Recent Changes (v0.1.10-0.1.12)

- **v0.1.12**: `--skip-child-links` is now opt-in (was auto-enabled with --relink)
- **v0.1.11**: index.md populates parent directory page (not child)
- **v0.1.10**: Image support + incremental sync via content hash
