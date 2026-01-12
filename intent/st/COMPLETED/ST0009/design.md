---
verblock: "12 Jan 2026:v0.1: matts - As-built design"
intent_version: 2.2.0
status: DONE
created: 20260112
completed: 20260112
---
# Design - ST0009: Image Support & Incremental Sync

## Problem Statement

Two related issues in the sync pipeline:

1. **Images silently dropped** - Markdown images (`![alt](url)`) fell through to the catch-all in `ast_to_blocks.ex` and were silently discarded.

2. **Incremental sync not implemented** - All files re-synced every time despite `content_hash` infrastructure existing in the codebase.

## Approach

### Issue 1: Image Support

Add image handler in `ast_to_blocks.ex` to convert external URL images to Notion image blocks.

**Key decisions**:
- External URLs (`http://`, `https://`) converted to Notion image blocks
- Relative paths and data URLs skipped silently (no warnings to reduce noise)
- Alt text used as image caption

### Issue 2: Incremental Sync

Enable the existing (but unused) `content_hash` infrastructure by checking `content_changed?` before updating pages.

**Key decisions**:
- SHA-256 hash stored in frontmatter `content_hash` field
- Files with unchanged hash skipped entirely (no API call)
- Files with nil hash sync once to populate the hash

## Design Decisions

### D1: Image URL Handling

**Decision**: Only external URLs converted; local paths skipped silently.

**Rationale**:
- Notion API requires absolute URLs for external images
- Relative paths would need `--base-url` option (deferred to future work)
- Silent skip avoids noise in output for common local image refs

### D2: Hash Comparison Target

**Decision**: Hash computed on markdown body, not rendered blocks.

**Rationale**:
- Body is stable source of truth
- Rendered blocks change when `--relink` resolves links
- Comparing body ensures only actual content changes trigger sync

### D3: Nil Hash Behavior

**Decision**: Nil hash treated as "changed" (triggers sync).

**Rationale**:
- Legacy files synced before hash feature have nil hash
- First sync after upgrade populates hash
- No manual migration required

## Architecture

### Image Block Flow

```
EarmarkParser produces:
  {"img", [{"src", "url"}, {"alt", "text"}], [], %{}}
                    |
                    v
  convert_node({"img", attrs, _, _}, opts)
                    |
                    v
  Check src: external URL? --> NotionBlock.image(url, alt)
            |
            relative/data? --> [] (skip silently)
```

### Incremental Sync Flow

```
sync_action called for file with notion_id
                    |
                    v
  content_changed?(body, stored_hash)
                    |
        +-----------+-----------+
        |                       |
    true (or nil)           false
        |                       |
        v                       v
  update_existing_page    {:ok, :skipped, notion_id}
  (API call, update hash)
```

## Alternatives Considered

### A1: Warn on skipped images

**Rejected because**:
- Too noisy for docs with many local images
- User already knows local images won't sync
- Silent skip is cleaner UX

### A2: Auto-upload local images to Notion

**Rejected because**:
- Notion doesn't support file uploads via API (only URLs)
- Would need external hosting (S3, etc.)
- Out of scope for this tool

### A3: Use file mtime for change detection

**Rejected because**:
- mtime changes on git checkout, file copy
- Not reliable indicator of content change
- Hash is deterministic and accurate
