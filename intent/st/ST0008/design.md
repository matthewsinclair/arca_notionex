---
verblock: "08 Jan 2026:v0.2: matts - Detailed bug analysis and fix plan"
intent_version: 2.2.0
status: WIP
created: 20260108
completed:
---
# Design - ST0008: Critical Bug Fixes - Directory Hierarchy & Title Management

## Approach

This steel thread fixes three critical bugs discovered during production sync testing. The approach is:

1. **Fail fast, not silent** - Replace silent fallbacks with proper error propagation
2. **Frontmatter as source of truth** - Titles stored explicitly, preserved bidirectionally
3. **Incremental sync** - Track content hashes to avoid unnecessary syncs
4. **Clear conflict resolution** - Explicit CLI flags for handling conflicts

## Design Decisions

### D1: Directory Creation Error Handling

**Decision**: Halt sync on directory creation failure, don't fall back to parent.

**Rationale**:

- Silent fallback causes cascade failures (all files go to wrong location)
- Better to fail early with clear error than create broken hierarchy
- User can fix the issue (auth, network) and retry

**Implementation**:

```elixir
# BEFORE: Silent fallback
case Client.create_page(parent_id, dir_title, []) do
  {:ok, response} -> response.id
  {:error, _, _} -> parent_id  # BAD: continues with wrong parent
end

# AFTER: Proper error propagation
case Client.create_page(parent_id, dir_title, []) do
  {:ok, response} -> {:ok, response.id}
  {:error, type, reason} -> {:error, type, reason}  # GOOD: halts sync
end
```

### D2: Smart Title Derivation for index.md

**Decision**: Use parent directory name as title for index.md files.

**Rationale**:

- `index.md` is a convention for "folder index" - title should reflect the folder
- Prevents confusing duplicate "Index" pages in Notion
- Intuitive: `architecture/index.md` becomes "Architecture"

**Algorithm**:

```
if filename == "index.md":
    if parent_dir == ".":
        title = "Index"  # Root index stays Index
    else:
        title = humanize(parent_dir)  # architecture -> "Architecture"
else:
    title = humanize(filename)  # my-doc.md -> "My Doc"
```

### D3: Per-Directory Title Uniqueness

**Decision**: Validate titles are unique within each directory, but allow duplicates across directories.

**Rationale**:

- Notion pages under same parent must have unique titles for clear navigation
- Cross-directory duplicates are fine (different context)
- Example: `docs/overview.md` and `api/overview.md` can both be "Overview"

### D4: Content Hash for Change Detection

**Decision**: Store SHA-256 hash of markdown body in frontmatter.

**Rationale**:

- Enables incremental sync (skip unchanged files)
- More reliable than file mtime (can be changed by git, copy operations)
- SHA-256 is fast and collision-resistant
- Stored with prefix `sha256:` for future extensibility

**Format**:

```yaml
---
title: "Architecture"
notion_id: "abc123..."
notion_synced_at: "2026-01-08T12:00:00Z"
content_hash: "sha256:a1b2c3d4..."
---
```

### D5: Conflict Resolution Strategy

**Decision**: Default to manual resolution; provide explicit flags for auto-resolution.

**Rationale**:

- Safest default: don't overwrite user work without consent
- Clear flags for when user knows what they want
- `--local-wins`: Push local changes, overwrite Notion
- `--notion-wins`: Pull Notion changes, overwrite local
- `--force`: Sync all files regardless of change status

## Architecture

### Data Flow: Sync Operation

```
┌─────────────────────────────────────────────────────────────────────────┐
│                          SYNC DATA FLOW                                 │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  1. DISCOVER FILES                                                      │
│     Path.wildcard("**/*.md") → [FileEntry.t()]                         │
│     Sort by depth (shallow first)                                       │
│                                                                         │
│  2. VALIDATE TITLES                                                     │
│     Group by parent_path → Check uniqueness per directory               │
│     Fail if duplicates found                                            │
│                                                                         │
│  3. FOR EACH FILE (depth-first order):                                  │
│                                                                         │
│     a) ENSURE PARENT PAGES                                              │
│        Check page_map for parent_path                                   │
│        If missing: create directory pages recursively                   │
│        Track in page_map: %{"arch" => page_id}                         │
│                                                                         │
│     b) CHECK IF SYNC NEEDED                                             │
│        - No notion_id? → CREATE                                         │
│        - Hash changed? → UPDATE                                         │
│        - Hash same?    → SKIP                                           │
│                                                                         │
│     c) SYNC FILE                                                        │
│        Parse frontmatter + body                                         │
│        Convert body → Notion blocks                                     │
│        Create/Update page via API                                       │
│        Update frontmatter (notion_id, synced_at, content_hash)         │
│                                                                         │
│  4. RETURN RESULT                                                       │
│     %SyncResult{created: [...], updated: [...], skipped: [...], ...}   │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

### Module Responsibilities

```
┌─────────────────────────────────────────────────────────────────────────┐
│                        MODULE ARCHITECTURE                              │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  sync.ex                                                                │
│  ├── sync_directory/2      - Main orchestration                         │
│  ├── discover_files/1      - Find all .md files                         │
│  ├── validate_unique_titles/1  - NEW: Check per-dir uniqueness          │
│  ├── sync_files/4          - Process files in order                     │
│  ├── ensure_parent_pages/5 - Create directory hierarchy                 │
│  ├── create_directory_pages/5  - REFACTOR: proper error handling        │
│  ├── should_sync?/4        - NEW: Change detection                      │
│  └── resolve_conflict/3    - NEW: Conflict resolution                   │
│                                                                         │
│  frontmatter.ex                                                         │
│  ├── parse/1               - Extract YAML from content                  │
│  ├── serialize/1           - Convert struct to YAML                     │
│  ├── derive_title_from_path/1  - NEW: Smart title for index.md          │
│  ├── ensure_frontmatter/1  - REFACTOR: Use smart derivation             │
│  ├── compute_hash/1        - NEW: SHA-256 of content                    │
│  ├── content_changed?/2    - NEW: Compare hashes                        │
│  └── set_notion_id/3       - REFACTOR: Include hash                     │
│                                                                         │
│  conflict.ex (NEW)                                                      │
│  ├── detect_conflict/2     - Compare local vs Notion state              │
│  └── conflict_status       - :no_conflict | :local | :notion | :both    │
│                                                                         │
│  schemas/frontmatter.ex                                                 │
│  └── content_hash field    - NEW: Store hash in schema                  │
│                                                                         │
│  commands/sync_command.ex                                               │
│  └── New flags: --force, --local-wins, --notion-wins                    │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

### Error Propagation Flow

```
┌─────────────────────────────────────────────────────────────────────────┐
│                      ERROR PROPAGATION                                  │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  Client.create_page fails                                               │
│        │                                                                │
│        ▼                                                                │
│  create_directory_page returns {:error, type, reason}                   │
│        │                                                                │
│        ▼                                                                │
│  create_directory_pages uses reduce_while, halts on error               │
│        │                                                                │
│        ▼                                                                │
│  ensure_parent_pages returns {:error, type, reason}                     │
│        │                                                                │
│        ▼                                                                │
│  sync_files adds error to SyncResult, continues to next file            │
│        │                                                                │
│        ▼                                                                │
│  User sees: "Error creating directory 'architecture': API error..."     │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

## Alternatives Considered

### A1: Use file mtime instead of content hash

**Rejected because**:

- mtime changes on git checkout, file copy, etc.
- Not reliable indicator of actual content change
- Hash is more accurate and deterministic

### A2: Require user to fix duplicate titles manually

**Rejected because**:

- Poor UX: user may not know why sync fails
- Smart derivation handles 90% of cases automatically
- Manual override still possible via frontmatter

### A3: Warn on duplicate titles but continue sync

**Rejected because**:

- Would create confusing state in Notion
- Multiple "Index" pages under same parent
- Better to fail early and require explicit unique titles

### A4: Silently skip files on directory creation failure

**Rejected because**:

- User wouldn't know files were skipped
- Partial sync is worse than no sync
- Clear error message enables user to fix and retry
