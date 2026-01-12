---
intent_version: 2.2.0
status: TODO
created: 20260112
completed:
---
# ST0010: index.md Should Populate Parent Directory Page

## Summary

When syncing directories containing `index.md`, notionex creates an empty directory page AND a separate child page for the index content. The index.md content should instead populate the directory page itself.

---

## Current Behavior

Local structure:
```
prototypes/
├── storyfield/
│   └── v0.1.0/
│       └── index.md  (title: "Storyfield v0.1.0")
└── frontdesk/
    └── v0.1.0/
        └── index.md  (title: "Frontdesk v0.1.0")
```

Resulting Notion structure:
```
Prototypes/
├── Storyfield/
│   └── V0.1.0/                    ← EMPTY directory page
│       └── Storyfield v0.1.0      ← Content from index.md (REDUNDANT LEVEL)
└── Frontdesk/
    └── V0.1.0/                    ← EMPTY directory page
        └── Frontdesk v0.1.0       ← Content from index.md (REDUNDANT LEVEL)
```

**Problems:**
1. Empty "V0.1.0" pages that serve no purpose
2. Extra navigation depth for users
3. Orphan pages flagged in audit
4. Inconsistent with how wikis/docs typically handle index files

---

## Expected Behavior

The `index.md` content should **become** the directory page:

```
Prototypes/
├── Storyfield/
│   └── V0.1.0                     ← Contains content from index.md
└── Frontdesk/
    └── V0.1.0                     ← Contains content from index.md
```

**Convention:** In most documentation systems (Jekyll, Hugo, Docusaurus, etc.), `index.md` or `index.html` in a directory IS that directory's content, not a child of it.

---

## Root Cause

In `lib/arca_notionex/sync.ex`, the `create_directory_pages/5` function creates empty placeholder pages for each path segment. Then `sync_file/3` creates the index.md as a separate child page.

The logic doesn't check if the file being synced is `index.md` - if so, it should use that content for the directory page rather than creating a child.

---

## Proposed Fix

### Option A: Merge index.md into directory page (Recommended)

When syncing `dir/index.md`:
1. Check if parent directory page already exists
2. If yes: Update that page with index.md content (don't create child)
3. If no: Create directory page WITH the index.md content

```elixir
# In sync.ex - detect index.md and handle specially
defp is_index_file?(file_path) do
  Path.basename(file_path) == "index.md"
end

# When syncing index.md, target the parent directory page
defp get_target_page_id(file, page_map, is_index) do
  if is_index do
    # Use the directory's page ID, not create a child
    Map.get(page_map, file.parent_path)
  else
    # Normal behavior - create as child
    Map.get(page_map, file.parent_path)
  end
end
```

### Option B: Don't create directory pages if index.md exists

Pre-scan for index.md files and skip directory page creation for those paths, letting the index.md become the directory page.

---

## Edge Cases

| Case | Handling |
|------|----------|
| Directory with only index.md | index.md becomes directory page |
| Directory with index.md + other files | index.md becomes directory page, others are children |
| Directory with no index.md | Create empty directory page (current behavior) |
| Nested index.md files | Each becomes its respective directory page |
| index.md with explicit title | Use title from frontmatter for directory page |

---

## Test Cases

```elixir
test "index.md populates parent directory page" do
  # Setup: dir/index.md with content
  # Sync
  # Assert: directory page has content, no child "Index" page
end

test "directory with index.md and other files" do
  # Setup: dir/index.md + dir/other.md
  # Sync  
  # Assert: dir page has index content, other.md is child
end

test "nested index.md files" do
  # Setup: a/index.md, a/b/index.md
  # Sync
  # Assert: both become their directory pages
end
```

---

## Files to Modify

| File | Changes |
|------|---------|
| `lib/arca_notionex/sync.ex` | Detect index.md, merge into directory page |
| `lib/arca_notionex/schemas/file_entry.ex` | Add `is_index?` field |
| `test/arca_notionex/sync_test.exs` | Add index.md handling tests |

---

## Priority

**High** - Creates confusing Notion structure and orphan pages for any nested directory with index.md files. Common pattern in documentation projects.

---

## Related

- Orphan pages shown in `notionex audit` are symptoms of this issue
- The "Start Here" pages in other directories work because they're explicitly named, not index.md
