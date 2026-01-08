# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
