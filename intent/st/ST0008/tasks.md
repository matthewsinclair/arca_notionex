---
verblock: "08 Jan 2026:v0.2: matts - Detailed bug analysis and fix plan"
intent_version: 2.2.0
status: WIP
created: 20260108
completed:
---
# Tasks - ST0008: Critical Bug Fixes - Directory Hierarchy & Title Management

## Phase 1: Fix Directory Flattening (P0 - CRITICAL)

### 1.1 Refactor create_directory_pages/5

- [ ] Extract `create_directory_page/3` helper function
- [ ] Return `{:ok, page_id}` or `{:error, type, reason}` from helper
- [ ] Change `create_directory_pages/5` to use `Enum.reduce_while`
- [ ] Return `{:ok, page_map, page_id}` or `{:error, type, reason}`
- [ ] Handle dry-run mode in helper function

### 1.2 Update ensure_parent_pages/5

- [ ] Update return type to handle errors
- [ ] Propagate `{:error, type, reason}` from `create_directory_pages`
- [ ] Keep `{page_map, page_id}` return for success case

### 1.3 Update sync_files/4

- [ ] Handle error tuple from `ensure_parent_pages`
- [ ] Add error to `SyncResult.errors` on failure
- [ ] Continue processing remaining files after error
- [ ] Update `page_map` only on success

### 1.4 Add unit tests for directory error handling

- [ ] Test: API error returns error tuple
- [ ] Test: `reduce_while` halts on first error
- [ ] Test: Error propagates to sync result
- [ ] Test: Dry-run mode works correctly

---

## Phase 2: Fix Title Management (P0 - CRITICAL)

### 2.1 Add derive_title_from_path/1 to frontmatter.ex

- [ ] Create public function `derive_title_from_path/1`
- [ ] Handle index.md: use parent directory name
- [ ] Handle root index.md: keep as "Index"
- [ ] Handle regular files: humanize filename
- [ ] Add @spec and @doc

### 2.2 Add humanize_name/1 helper

- [ ] Replace hyphens and underscores with spaces
- [ ] Capitalize each word
- [ ] Handle edge cases (empty string, single char)

### 2.3 Update ensure_frontmatter/1

- [ ] Check if title is meaningful (not "Index", not empty)
- [ ] Use `derive_title_from_path/1` for smart derivation
- [ ] Override generic "Index" with derived title
- [ ] Keep user-specified titles that aren't "Index"

### 2.4 Add validate_unique_titles/1 to sync.ex

- [ ] Group files by `parent_path`
- [ ] Within each group, find duplicate titles
- [ ] Return `:ok` if all unique
- [ ] Return `{:error, :duplicate_titles, message}` with details

### 2.5 Call validation in sync_directory/2

- [ ] Add validation step after `discover_files`
- [ ] Fail fast if duplicates found
- [ ] Clear error message listing duplicates

### 2.6 Add unit tests for title handling

- [ ] Test: `index.md` in subdir gets parent name
- [ ] Test: Root `index.md` stays "Index"
- [ ] Test: Regular files get humanized name
- [ ] Test: Per-directory uniqueness validation
- [ ] Test: Cross-directory duplicates allowed

---

## Phase 3: Incremental Sync (P1)

### 3.1 Add content_hash field to Frontmatter schema

- [ ] Add `field :content_hash, :string` to embedded_schema
- [ ] Update changeset to cast content_hash
- [ ] Update type spec

### 3.2 Add hash functions to frontmatter.ex

- [ ] Add `compute_hash/1` - SHA-256 with prefix
- [ ] Add `content_changed?/2` - compare current vs stored
- [ ] Handle nil stored hash (first sync)
- [ ] Add @spec and @doc

### 3.3 Update frontmatter serialization

- [ ] Include content_hash in `serialize/1`
- [ ] Parse content_hash in `build_frontmatter/1`

### 3.4 Update set_notion_id to include hash

- [ ] Change signature to `set_notion_id/3` (add body param)
- [ ] Compute and store hash along with notion_id
- [ ] Update all callers

### 3.5 Add should_sync?/4 to sync.ex

- [ ] Check for --force flag
- [ ] Check if notion_id is nil (new file)
- [ ] Check if content hash changed
- [ ] Return `{:sync, reason}` or `{:skip, :no_changes}`

### 3.6 Integrate change detection into sync_file

- [ ] Call `should_sync?` before processing
- [ ] Skip files with no changes
- [ ] Track skipped files in result

### 3.7 Create conflict.ex module

- [ ] Define conflict_status type
- [ ] Add `detect_conflict/2` function
- [ ] Compare local hash vs stored hash
- [ ] Compare notion last_edited vs synced_at

### 3.8 Add conflict resolution to sync.ex

- [ ] Add `resolve_conflict/3` function
- [ ] Handle --local-wins flag
- [ ] Handle --notion-wins flag
- [ ] Default to manual (error on conflict)

### 3.9 Add CLI flags to sync_command.ex

- [ ] Add --force flag
- [ ] Add --local-wins flag
- [ ] Add --notion-wins flag
- [ ] Update help text
- [ ] Pass flags to sync options

### 3.10 Add unit tests for incremental sync

- [ ] Test: Hash computation
- [ ] Test: Content changed detection
- [ ] Test: Skip unchanged files
- [ ] Test: --force syncs all
- [ ] Test: Conflict detection
- [ ] Test: --local-wins resolution
- [ ] Test: --notion-wins resolution

---

## Phase 4: Notion Formatting Preservation (P2)

### 4.1 Verify HTML comment parsing in ast_to_blocks.ex

- [ ] Check underline comment handling
- [ ] Check color comment handling
- [ ] Add test for round-trip preservation

### 4.2 Verify HTML comment generation in blocks_to_markdown.ex

- [ ] Check underline rendering
- [ ] Check color rendering
- [ ] Add test for round-trip preservation

### 4.3 Add round-trip test

- [ ] Create markdown with notion comments
- [ ] Convert to blocks and back
- [ ] Verify formatting preserved

---

## Final Tasks

### Update documentation

- [ ] Update README.md with new flags
- [ ] Update completions.txt with new flags
- [ ] Update CHANGELOG.md

### Run full test suite

- [ ] Ensure all existing tests pass
- [ ] Run new tests
- [ ] Manual testing with real Notion

---

## Task Notes

### Priority Order

Execute phases in order: P0 bugs first (Phase 1, 2), then P1 features (Phase 3), then P2 verification (Phase 4).

### Testing Strategy

- Unit tests for each new function
- Integration tests for full sync flow
- Manual testing against real Notion workspace recommended after each phase

### Backwards Compatibility

- `content_hash` will be nil for existing synced files
- First sync after update will sync all files (nil hash = changed)
- No breaking changes to CLI interface

## Dependencies

```
Phase 1 ─┐
         ├─> Phase 3 (needs error handling in place)
Phase 2 ─┘

Phase 4 can run in parallel (independent verification)
```
