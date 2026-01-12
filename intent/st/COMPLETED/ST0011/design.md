---
verblock: "12 Jan 2026:v0.1: matts - As-built design"
intent_version: 2.2.0
status: DONE
created: 20260112
completed: 20260112
---
# Design - ST0011: Link resolution and skip_child_links fix

## Problem Statement

The `skip_child_links` feature was auto-enabled with `--relink`, incorrectly stripping links based on **filesystem directory structure** rather than **Notion's actual page hierarchy**.

Example:
```
Filesystem:                          Notion hierarchy:
a3-product/                          [Shared Parent]
  index.md                             +-- A3 Product
  methodology/                         +-- Methodology  <-- PEER, not child!
    index.md
```

The `is_child_link?` function saw `methodology/index.md` as a "child" because it's in a subdirectory. But in Notion they're **siblings** under a shared parent.

**Result**: ALL navigation links to subdirectories were stripped when using `--relink`, even for peer pages.

## Approach

**Solution: Make skip_child_links Opt-In**

Changed `skip_child_links` from auto-enabled with `--relink` to **opt-in via explicit `--skip-child-links` flag**.

This was the safest fix because:
- No API calls needed (checking Notion hierarchy would require API queries)
- Users who need the behavior can explicitly enable it
- Default behavior preserves all links (no silent data loss)

## Design Decisions

### D1: Opt-In vs Auto-Detection

**Decision**: Opt-in via explicit flag.

**Rationale**:
- Auto-detection would require querying Notion API for each linked page's parent
- Adds complexity and latency to sync
- Users know their document structure better than we can infer
- Explicit flag is simple, predictable, and documented

### D2: Flag Scope

**Decision**: `--skip-child-links` is independent of `--relink`.

**Rationale**:
- Separation of concerns: `--relink` resolves links, `--skip-child-links` filters them
- Can use either flag independently (though `--skip-child-links` only matters with `--relink`)
- Clear mental model for users

## Architecture

### CLI Flag Flow

```
User runs: notionex sync --dir ./docs --relink --skip-child-links
                              |           |              |
                              v           v              v
                         sync_command.ex extracts options
                              |
                              v
                    Sync.sync_directory(dir, opts)
                              |
                              v
                    sync_opts = [skip_child_links: true, ...]
                              |
                              v
                    AstToBlocks.convert(body, sync_opts)
                              |
                              v
                    resolve_link checks is_child_link?
                              |
                              v
                    If child AND skip_child_links: plain text
                    Otherwise: page mention
```

## Alternatives Considered

### A1: Query Notion API for Parent Hierarchy

**Rejected because**:
- Requires API call per linked page to determine true parent
- Adds significant latency to sync
- Rate limit implications for large doc sets
- Over-engineering for edge case

### A2: Use frontmatter to specify relationships

**Rejected because**:
- Requires manual metadata maintenance
- Error-prone and tedious for users
- Existing filesystem structure is sufficient when used correctly

### A3: Always preserve links (remove skip_child_links entirely)

**Rejected because**:
- Some users legitimately need to skip auto-generated child links
- Feature has valid use case, just wrong default
