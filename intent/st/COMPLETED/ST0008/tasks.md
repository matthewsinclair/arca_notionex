---
verblock: "08 Jan 2026:v0.3: matts - All phases complete"
intent_version: 2.2.0
status: DONE
created: 20260108
completed: 20260108
---
# Tasks - ST0008: Critical Bug Fixes - Directory Hierarchy & Title Management

## Phase 1: Fix Directory Flattening (P0 - CRITICAL)

### 1.1 Refactor create_directory_pages/5

- [x] Extract `create_directory_page/3` helper function
- [x] Return `{:ok, page_id}` or `{:error, type, reason}` from helper
- [x] Change `create_directory_pages/5` to use `Enum.reduce_while`
- [x] Return `{:ok, page_map, page_id}` or `{:error, type, reason}`
- [x] Handle dry-run mode in helper function

### 1.2 Update ensure_parent_pages/5

- [x] Update return type to handle errors
- [x] Propagate `{:error, type, reason}` from `create_directory_pages`
- [x] Keep `{page_map, page_id}` return for success case

### 1.3 Update sync_files/4

- [x] Handle error tuple from `ensure_parent_pages`
- [x] Add error to `SyncResult.errors` on failure
- [x] Continue processing remaining files after error
- [x] Update `page_map` only on success

### 1.4 Add unit tests for directory error handling

- [x] Test: API error returns error tuple
- [x] Test: `reduce_while` halts on first error
- [x] Test: Error propagates to sync result
- [x] Test: Dry-run mode works correctly

---

## Phase 2: Fix Title Management (P0 - CRITICAL)

### 2.1 Add derive_title_from_path/1 to frontmatter.ex

- [x] Create public function `derive_title_from_path/1`
- [x] Handle index.md: use parent directory name
- [x] Handle root index.md: keep as "Index"
- [x] Handle regular files: humanize filename
- [x] Add @spec and @doc

### 2.2 Add humanize_name/1 helper

- [x] Replace hyphens and underscores with spaces
- [x] Capitalize each word
- [x] Handle edge cases (empty string, single char)

### 2.3 Update ensure_frontmatter/1

- [x] Check if title is meaningful (not "Index", not empty)
- [x] Use `derive_title_from_path/1` for smart derivation
- [x] Override generic "Index" with derived title
- [x] Keep user-specified titles that aren't "Index"

### 2.4 Add validate_unique_titles/1 to sync.ex

- [x] Group files by `parent_path`
- [x] Within each group, find duplicate titles
- [x] Return `:ok` if all unique
- [x] Return `{:error, :duplicate_titles, message}` with details

### 2.5 Call validation in sync_directory/2

- [x] Add validation step after `discover_files`
- [x] Fail fast if duplicates found
- [x] Clear error message listing duplicates

### 2.6 Add unit tests for title handling

- [x] Test: `index.md` in subdir gets parent name
- [x] Test: Root `index.md` stays "Index"
- [x] Test: Regular files get humanized name
- [x] Test: Per-directory uniqueness validation
- [x] Test: Cross-directory duplicates allowed

---

## Phase 3: Incremental Sync (P1)

### 3.1 Add content_hash field to Frontmatter schema

- [x] Add `field :content_hash, :string` to embedded_schema
- [x] Update changeset to cast content_hash
- [x] Update type spec

### 3.2 Add hash functions to frontmatter.ex

- [x] Add `compute_hash/1` - SHA-256 with prefix
- [x] Add `content_changed?/2` - compare current vs stored
- [x] Handle nil stored hash (first sync)
- [x] Add @spec and @doc

### 3.3 Update frontmatter serialization

- [x] Include content_hash in `serialize/1`
- [x] Parse content_hash in `build_frontmatter/1`

### 3.4 Update set_notion_id to include hash

- [x] Change signature to `set_notion_id/3` (add body param)
- [x] Compute and store hash along with notion_id
- [x] Update all callers

### 3.5 Add should_sync?/4 to sync.ex (DEFERRED)

- [ ] Check for --force flag
- [ ] Check if notion_id is nil (new file)
- [ ] Check if content hash changed
- [ ] Return `{:sync, reason}` or `{:skip, :no_changes}`

### 3.6 Integrate change detection into sync_file (DEFERRED)

- [ ] Call `should_sync?` before processing
- [ ] Skip files with no changes
- [ ] Track skipped files in result

### 3.7 Create conflict.ex module (DEFERRED)

- [ ] Define conflict_status type
- [ ] Add `detect_conflict/2` function
- [ ] Compare local hash vs stored hash
- [ ] Compare notion last_edited vs synced_at

### 3.8 Add conflict resolution to sync.ex (DEFERRED)

- [ ] Add `resolve_conflict/3` function
- [ ] Handle --local-wins flag
- [ ] Handle --notion-wins flag
- [ ] Default to manual (error on conflict)

### 3.9 Add CLI flags to sync_command.ex (DEFERRED)

- [ ] Add --force flag
- [ ] Add --local-wins flag
- [ ] Add --notion-wins flag
- [ ] Update help text
- [ ] Pass flags to sync options

### 3.10 Add unit tests for incremental sync

- [x] Test: Hash computation
- [x] Test: Content changed detection
- [ ] Test: Skip unchanged files (DEFERRED)
- [ ] Test: --force syncs all (DEFERRED)
- [ ] Test: Conflict detection (DEFERRED)
- [ ] Test: --local-wins resolution (DEFERRED)
- [ ] Test: --notion-wins resolution (DEFERRED)

---

## Phase 4: Notion Formatting Preservation (P2)

### 4.1 Verify HTML comment parsing in ast_to_blocks.ex

- [x] Check underline comment handling
- [x] Check color comment handling
- [x] Add test for round-trip preservation

### 4.2 Verify HTML comment generation in blocks_to_markdown.ex

- [x] Check underline rendering
- [x] Check color rendering
- [x] Add test for round-trip preservation

### 4.3 Add round-trip test

- [x] Create markdown with notion comments
- [x] Convert to blocks and back
- [x] Verify formatting preserved

---

## Final Tasks

### Update documentation

- [x] Update CHANGELOG.md

### Run full test suite

- [x] Ensure all existing tests pass (187 tests, 0 failures)
- [x] Run new tests
- [x] Manual testing with real Notion

---

## Follow-up Tasks (Added Post-Initial Implementation)

### Code Quality

- [x] Refactor `case true/false` to pattern-matched functions
- [x] Eliminate double file read in sync_files
- [x] Add tests with capture_io for output functions

### Infrastructure

- [x] Add GitHub Actions CI workflow
- [x] Add .tool-versions for Erlang/Elixir versions
- [x] Add MIT License

### CLI Improvements

- [x] Implement two-pass --relink in single command
- [x] Refactor audit table to Ctx flow with Owl rendering
- [x] Implement --version/-v flags

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
