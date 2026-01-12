# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.12] - 2026-01-12

### Fixed

- **Link resolution to page mentions** - Internal `.md` links now correctly resolve to Notion page mentions when using `--relink`. Added comprehensive tests covering nested directory structures and relative path resolution.

- **skip_child_links now opt-in** - The `--skip-child-links` flag is now a separate opt-in option instead of being auto-enabled with `--relink`. This fixes a bug where links to filesystem subdirectories were incorrectly stripped even when those pages were peers (not children) in Notion's hierarchy. Use `--skip-child-links` only when your filesystem subdirectories truly represent Notion child pages.

### Added

- **`--skip-child-links` CLI flag** - New flag for sync command to skip rendering links to filesystem subdirectories. Use this when subdirectories represent actual Notion child pages (which Notion displays automatically).

- **`LinkMap.is_child_link?/2`** - New function to detect links that point to subdirectories. Used internally when `--skip-child-links` is enabled.

### Tests

- Added 11 new tests for `is_child_link?` in `link_map_test.exs`
- Added 5 new tests for `skip_child_links` option in `ast_to_blocks_test.exs`
- Added 2 new tests for ST0011 scenario in `ast_to_blocks_test.exs`
- Total: 222 tests, 0 failures

## [0.1.11] - 2026-01-12

### Fixed

- **index.md populates parent directory page** - When syncing directories containing `index.md`, the content now populates the directory page itself instead of creating a redundant child page. This matches the convention used by Jekyll, Hugo, Docusaurus, etc. The directory page's notion_id is stored in the index.md frontmatter for subsequent updates.

### Tests

- Added 2 new tests for index.md handling in `sync_test.exs`
- Total: 199 tests, 0 failures

## [0.1.10] - 2026-01-12

### Added

- **Image support** - Markdown images (`![alt](url)`) now convert to Notion image blocks. External URLs (http/https) are fully supported. Relative paths and data URLs are skipped with warnings.

- **Incremental sync** - Files are now skipped during sync if their content hasn't changed (based on SHA-256 content hash). This dramatically reduces API calls and sync time for large doc sets. Files synced before this version will sync once to populate their hash.

### Changed

- Paragraph handler now extracts standalone images as block-level elements (required because EarmarkParser wraps images in `<p>` tags).

### Tests

- Added 8 new image conversion tests in `ast_to_blocks_test.exs`
- Added 2 new incremental sync tests in `sync_test.exs`
- Total: 197 tests, 0 failures

## [0.1.9] - 2026-01-09

### Fixed

- **Audit: Files with notion_id shown as unlinked** - Files with `notion_id` in frontmatter were incorrectly showing `Notion: -` because scan only checked immediate children. Now uses recursive scanning to find all nested pages.

- **Audit: Directory pages shown as orphans** - Container pages created by notionex for directories (e.g., "Team") were incorrectly marked as `[orphan page]` with `Action: DELETE`. Now recognized as `[directory]` with `Action: -` using title matching + has-children heuristic.

### Added

- **Recursive Notion page scanning** - `scan_notion_pages/1` now recursively fetches all descendant pages, enabling proper audit of nested directory structures.

- **AuditEntry.unverified/4** - New entry type for files with `notion_id` but page not found in scan. Shows `? (id...)` in Notion column instead of discarding the notion_id.

- **AuditEntry.directory_page/2** - New entry type for structural container pages. Displays as `[directory]` instead of `[orphan page]`.

## [0.1.8] - 2026-01-08

### Fixed

- **CLI --version flag** - Implemented `--version` and `-v` flags in CLI entry point. Previously mentioned in help but not functional.

- **Dynamic version reading** - `ArcaNotionex.version/0` now reads from config instead of returning hardcoded value.

## [0.1.7] - 2026-01-08

### Added

- **MIT License** - Added LICENSE file with MIT license for open source distribution.

## [0.1.6] - 2026-01-08

### Changed

- **Audit command table rendering** - Refactored audit command to use proper Arca.Cli `Ctx` flow and Owl-based table rendering instead of raw TableRex output. Tables now render cleanly with proper styling.

### Added

- **GitHub Actions CI** - Added `.github/workflows/ci.yml` for automated testing on push/PR to main. Runs compile, format check, and tests.

- **Tool versions** - Added `.tool-versions` specifying Erlang 28.0 and Elixir 1.19.4.

## [0.1.5] - 2026-01-08

### Added

- **Two-pass --relink** - When `--relink` is used with new files (no notion_id), sync now automatically does two passes: Pass 1 creates pages and writes notion_ids, Pass 2 rebuilds LinkMap and resolves internal links. No more need to run sync twice.

### Changed

- **Refactored sync_files** - Replaced non-idiomatic `case true/false` with pattern-matched `sync_single_file/8` function heads.

- **Eliminated double file read** - Files are now read once via `read_and_parse_file/1` and the parsed frontmatter is used for branching, improving efficiency.

### Tests

- Added 5 new tests for notion_id optimization and two-pass --relink behavior.
- Total: 187 tests, 0 failures.

## [0.1.4] - 2026-01-08

### Fixed

- **Directory flattening bug** - Fixed silent fallback in `create_directory_pages` that caused all pages to be created flat under root instead of nested hierarchy. Now properly propagates errors with `Enum.reduce_while`.

- **Duplicate "Index" titles** - Smart title derivation for `index.md` files now uses parent directory name (e.g., `architecture/index.md` becomes "Architecture"). Added per-directory title uniqueness validation.

### Added

- **Content hash tracking** - Added `content_hash` field to frontmatter schema with SHA-256 hashing for future incremental sync support.

- **Title validation** - `validate_unique_titles/2` checks for duplicate titles within each directory before sync.

### Changed

- Refactored `sync.ex` and `frontmatter.ex` to use pattern-matched functions instead of if/case/cond statements.

### Tests

- Added `sync_test.exs` with 24 new tests for directory discovery, sync operations, and title validation.
- Added 14 new tests to `frontmatter_test.exs` for title derivation and hash functions.
- Total: 182 tests, 0 failures.

## [0.1.3] - 2026-01-08

### Changed

- **Native page mentions** - Internal links now use Notion's native page mention format instead of URL links. This provides direct in-app navigation without browser redirects, and renders with the linked page's icon and title.

### Fixed

- **Text merging bug** - Fixed `merge_adjacent_text` incorrectly merging page mentions with regular text.

## [0.1.2] - 2026-01-08

### Fixed

- **CLI version display** - Configurator now reads version from VERSION.md instead of hardcoded value.

## [0.1.1] - 2026-01-08

### Fixed

- **Notion URL format** - Strip hyphens from UUID in generated Notion URLs. Notion expects 32-char hex without hyphens (e.g., `https://notion.so/2e201c86169781b2afd9deeff19e8a56` not `https://notion.so/2e201c86-1697-81b2-afd9-deeff19e8a56`).

## [0.1.0] - 2026-01-08

### Added

#### Core Features

- **Markdown to Notion sync** - Push local markdown files to Notion pages
- **Notion to Markdown pull** - Pull Notion pages back to local markdown files
- **Bidirectional link resolution** - Internal `.md` links converted to Notion URLs and back
- **Hierarchical sync** - Subdirectories become nested Notion pages
- **Frontmatter management** - Automatic tracking of `notion_id` and `notion_synced_at`

#### CLI Commands

- `notionex prepare` - Add YAML frontmatter to markdown files
- `notionex audit` - Compare local files vs Notion pages
- `notionex sync` - Push markdown to Notion (create/update)
- `notionex pull` - Pull from Notion to local markdown

#### Sync Features

- `--dry-run` flag for previewing changes
- `--relink` flag for resolving internal markdown links to Notion URLs
- Automatic page creation for new files
- Automatic page updates for existing files
- Directory structure preserved as nested pages

#### Pull Features

- `--scope linked-only` - Only pull files with existing `notion_id`
- `--scope all-children` - Pull all child pages, create new local files
- `--scope list` - Pull specific page IDs
- Conflict resolution: `--conflict manual|local-wins|notion-wins|newest-wins`

#### Block Type Support

- Headings (h1-h6, mapped to Notion's h1-h3)
- Paragraphs with rich text (bold, italic, code, strikethrough)
- Bulleted and numbered lists with nesting
- Code blocks with language detection
- Blockquotes
- Tables (GFM format)
- Links (internal and external)

#### Fidelity Preservation

- Notion-specific formatting preserved in HTML comments
- Underline: `<!-- notion:underline -->text<!-- /notion:underline -->`
- Color: `<!-- notion:color=red -->text<!-- /notion:color -->`

### Technical Details

- Built on Elixir with Ecto schemas for typed data
- Uses EarmarkParser for markdown AST
- Notion API client with rate limiting (3 req/sec)
- 145 unit tests passing
