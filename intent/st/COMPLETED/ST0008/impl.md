---
verblock: "08 Jan 2026:v0.4: matts - Final as-built with follow-up refinements"
intent_version: 2.2.0
status: COMPLETE
created: 20260108
completed: 20260108
---
# Implementation - ST0008: Critical Bug Fixes - Directory Hierarchy & Title Management

> **Note**: This document records as-built implementation details.

## Implementation Log

### Phase 1: Directory Flattening Fix

**Status**: COMPLETE

**Files Modified**:

- [x] `lib/arca_notionex/sync.ex`
- [x] `test/arca_notionex/sync_test.exs` (new file)

**Key Changes**:

- Refactored `create_directory_pages/5` to use `Enum.reduce_while` with proper error propagation
- Extracted `create_directory_page/3` helper returning `{:ok, page_id}` or `{:error, type, reason}`
- Updated `ensure_parent_pages/5` to return `{:ok, page_map, page_id}` tuple
- Updated `sync_files/4` to handle error tuples and continue processing remaining files
- Created `sync_test.exs` with 24 tests covering directory discovery, sync, and error handling

---

### Phase 2: Title Management Fix

**Status**: COMPLETE

**Files Modified**:

- [x] `lib/arca_notionex/frontmatter.ex`
- [x] `lib/arca_notionex/sync.ex`
- [x] `test/arca_notionex/frontmatter_test.exs`
- [x] `test/arca_notionex/sync_test.exs`

**Key Changes**:

- Made `derive_title_from_path/1` public with smart `index.md` handling
- Refactored to use pattern-matched functions instead of if/case/cond
- Added `validate_unique_titles/2` with per-directory uniqueness checking
- Wired validation into `sync_directory/2` before sync
- Added tests for title derivation (5 tests) and validation (6 tests)

**Pattern Matching Refactor**:

```elixir
# Before (if/case)
def derive_title_from_path(file_path) do
  if basename == "index" do
    case Path.dirname() |> Path.basename() do
      "." -> "Index"
      parent_dir -> humanize_name(parent_dir)
    end
  else
    humanize_name(basename)
  end
end

# After (pattern matched)
def derive_title_from_path(file_path) do
  file_path
  |> Path.basename(".md")
  |> derive_title_from_basename(file_path)
end

defp derive_title_from_basename("index", file_path) do
  file_path |> Path.dirname() |> Path.basename() |> derive_title_for_index()
end
defp derive_title_from_basename(basename, _file_path), do: humanize_name(basename)

defp derive_title_for_index("."), do: "Index"
defp derive_title_for_index(parent_dir), do: humanize_name(parent_dir)
```

---

### Phase 3: Incremental Sync

**Status**: COMPLETE (core functionality)

**Files Modified**:

- [x] `lib/arca_notionex/schemas/frontmatter.ex`
- [x] `lib/arca_notionex/frontmatter.ex`
- [x] `lib/arca_notionex/sync.ex`
- [x] `test/arca_notionex/frontmatter_test.exs`

**Key Changes**:

- Added `content_hash` field to Frontmatter schema
- Added `compute_hash/1` (SHA-256 with prefix)
- Added `content_changed?/2` for change detection
- Updated `set_notion_id/3` to accept optional body for hash computation
- Updated `update_synced_at/2` to accept optional body for hash computation
- Refactored `sync_file` to use pattern-matched `sync_action` helpers
- Added 6 tests for hash computation and change detection

**Note**: CLI flags (`--force`, `--local-wins`, `--notion-wins`) deferred to future work.

---

### Phase 4: Formatting Preservation

**Status**: VERIFIED (already implemented)

**Files Verified**:

- [x] `lib/arca_notionex/blocks_to_markdown.ex`
- [x] `test/arca_notionex/blocks_to_markdown_test.exs`

**Findings**:

- HTML comment preservation already fully implemented
- Tests exist for underline and color preservation
- Round-trip test verifies formatting survives sync cycle

---

## Test Results

### Unit Tests Added

- `sync_test.exs`: 24 new tests
  - discover_files/1: 6 tests
  - sync_directory/2: 4 tests
  - sync_file/3: 5 tests
  - FileEntry creation: 2 tests
  - validate_unique_titles/2: 6 tests
  - title validation integration: 1 test

- `frontmatter_test.exs`: 14 new tests
  - derive_title_from_path/1: 5 tests
  - compute_hash/1: 3 tests
  - content_changed?/2: 3 tests
  - ensure_frontmatter/1: 3 tests

### Test Coverage

```
182 tests, 0 failures
```

All existing tests continue to pass. Total test count increased from 145 to 182.

---

### Follow-up: Code Refinements & Infrastructure

**Status**: COMPLETE

**Files Modified**:

- [x] `lib/arca_notionex/sync.ex` - Pattern matching refactor, two-pass --relink
- [x] `lib/arca_notionex/audit.ex` - Added `format_for_ctx/1` for Ctx flow
- [x] `lib/arca_notionex/commands/audit_command.ex` - Refactored to Ctx flow with Owl tables
- [x] `lib/arca_notionex/cli.ex` - Added --version/-v flag handling
- [x] `lib/arca_notionex.ex` - Dynamic version reading from config
- [x] `test/arca_notionex/sync_test.exs` - Added 5 tests with capture_io
- [x] `test/arca_notionex_test.exs` - Updated version test
- [x] `.github/workflows/ci.yml` - New GitHub Actions CI workflow
- [x] `.tool-versions` - Erlang 28.0, Elixir 1.19.4
- [x] `LICENSE` - MIT license for open source

**Key Changes**:

1. **Pattern Matching Refactor**: Replaced non-idiomatic `case true/false` with pattern-matched `sync_single_file/8` function heads
2. **Double Read Elimination**: Added `read_and_parse_file/1` to read file once, branch based on frontmatter
3. **Two-Pass --relink**: Single command now does Pass 1/2 (create pages) then Pass 2/2 (resolve links) automatically
4. **Audit Table Rendering**: Refactored from raw TableRex to Arca.Cli Ctx flow with `{:table, rows, [has_headers: true]}`
5. **GitHub Actions CI**: Automated testing on push/PR to main (compile, format check, tests)
6. **--version Flag**: Implemented `--version` and `-v` in CLI entry point (was mentioned in help but never worked)

---

## Test Results (Final)

```
187 tests, 0 failures
```

Test count progression: 145 → 182 → 187

---

## Version History

| Date       | Version | Changes                                        |
|------------|---------|------------------------------------------------|
| 2026-01-08 | 0.2     | Initial plan documented                        |
| 2026-01-08 | 0.3     | Implementation complete - Phases 1-4 done      |
| 2026-01-08 | 0.4     | Follow-up: code refinements, CI, --version fix |

## Release History

| Version | Highlights                                               |
|---------|----------------------------------------------------------|
| 0.1.4   | Directory flattening fix, title management, content hash |
| 0.1.5   | Two-pass --relink, pattern matching refactor             |
| 0.1.6   | Audit table Ctx flow, GitHub Actions CI                  |
| 0.1.7   | MIT License                                              |
| 0.1.8   | --version flag fix                                       |
