---
verblock: "12 Jan 2026:v0.3: matts - All docs updated, project idle"
---
# Work In Progress

## Current Status

**All steel threads complete** - No active development work.

Version: 0.1.12 (222 tests, 0 failures)

## Recently Completed

**ST0011: Link resolution and duplicate subpage handling**
- Fixed `skip_child_links` to be opt-in via `--skip-child-links` flag
- Verified link resolution to page mentions working correctly
- Added 18 new tests

**ST0010: index.md populates parent directory page** (v0.1.11)
- index.md content now populates directory page instead of creating child

**ST0009: Image support and incremental sync** (v0.1.10)
- Markdown images convert to Notion image blocks
- Incremental sync skips unchanged files based on content hash

## Completed Steel Threads

| ID | Title | Version |
|----|-------|---------|
| ST0011 | Link resolution and skip_child_links fix | 0.1.12 |
| ST0010 | index.md populates parent directory | 0.1.11 |
| ST0009 | Image support and incremental sync | 0.1.10 |
| ST0008 | Audit command fixes | 0.1.9 |
| ST0007 | Two-pass relink | 0.1.5 |
| ST0006 | Pull command | 0.1.0 |
| ST0005 | Directory hierarchy | 0.1.0 |
| ST0004 | Sync command | 0.1.0 |
| ST0003 | Block conversion | 0.1.0 |
| ST0002 | Frontmatter | 0.1.0 |
| ST0001 | Project setup | 0.1.0 |

## Potential Future Work

- `--base-url` option to convert relative image paths to full URLs
- `--force` flag to bypass content hash check
- Table of contents generation
- Notion-to-markdown fidelity improvements

## Context for LLM

This document captures the current state of development. When starting a new session:

1. Check `intent/restart.md` for session context
2. Review recent steel threads in `intent/st/COMPLETED/`
3. Use `intent st list` to see all steel threads
4. Use `intent st new "Title"` to create new work items
