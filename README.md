# notionex

Bidirectional sync between local Markdown files and Notion pages.

## Features

- **Push to Notion** - Sync local markdown files to Notion pages
- **Pull from Notion** - Pull Notion pages back to local markdown
- **Link Resolution** - Internal `.md` links converted to Notion URLs (and back)
- **Hierarchical Sync** - Directory structure preserved as nested pages
- **Conflict Resolution** - Multiple strategies for handling sync conflicts
- **Frontmatter Tracking** - Automatic `notion_id` and sync timestamp management

## Installation

### Prerequisites

- Elixir 1.18+
- A Notion API token ([create one here](https://www.notion.so/my-integrations))

### Install as escript

```bash
git clone https://github.com/matthewsinclair/arca_notionex.git
cd arca_notionex
mix deps.get
mix escript.install
```

The `notionex` command will be installed to `~/.mix/escripts/`.

### Environment Setup

Set your Notion API token:

```bash
export NOTION_API_TOKEN="your-token-here"
```

## Commands

### prepare

Add YAML frontmatter to markdown files:

```bash
notionex prepare --dir ./docs
```

Adds a `title` field derived from the filename to files without frontmatter.

### sync

Push markdown files to Notion:

```bash
# Initial sync - creates pages
notionex sync --dir ./docs --root-page <PAGE_ID>

# With link resolution - converts .md links to Notion URLs
notionex sync --dir ./docs --root-page <PAGE_ID> --relink

# Preview without changes
notionex sync --dir ./docs --root-page <PAGE_ID> --dry-run
```

### pull

Pull pages from Notion to local markdown:

```bash
# Pull files that have notion_id in frontmatter
notionex pull --dir ./docs --root-page <PAGE_ID>

# Pull all child pages (creates new files)
notionex pull --dir ./docs --root-page <PAGE_ID> --scope all-children

# With conflict resolution
notionex pull --dir ./docs --root-page <PAGE_ID> --conflict notion-wins
```

**Conflict resolution options:**

- `manual` (default) - Only pull if Notion is newer and local unchanged
- `local-wins` - Never overwrite local files
- `notion-wins` - Always use Notion version
- `newest-wins` - Compare timestamps, most recent wins

### audit

Compare local files with Notion state:

```bash
notionex audit --dir ./docs --root-page <PAGE_ID>
```

## Workflow

### Initial Setup

```bash
# 1. Prepare files (adds frontmatter)
notionex prepare --dir ./docs

# 2. First sync (creates pages, populates notion_id)
notionex sync --dir ./docs --root-page <PAGE_ID>

# 3. Second sync with --relink (resolves internal links)
notionex sync --dir ./docs --root-page <PAGE_ID> --relink
```

### Ongoing Sync

```bash
# Push local changes to Notion
notionex sync --dir ./docs --root-page <PAGE_ID> --relink

# Pull Notion changes to local
notionex pull --dir ./docs --root-page <PAGE_ID>
```

## Frontmatter

After syncing, files contain:

```yaml
---
title: "Page Title"
notion_id: "abc123def456..."
notion_synced_at: "2026-01-08T12:00:00Z"
---
```

- `title` - Page title in Notion
- `notion_id` - Links the file to its Notion page
- `notion_synced_at` - Last sync timestamp for conflict detection

## Supported Markdown

| Element | Notion Block |
|---------|--------------|
| `# H1` - `### H3` | Headings 1-3 |
| `#### H4` - `###### H6` | Heading 3 (Notion max) |
| Paragraphs | Paragraph |
| `**bold**`, `*italic*`, `` `code` `` | Rich text annotations |
| `[link](url)` | Links (internal `.md` resolved) |
| `- item` | Bulleted list |
| `1. item` | Numbered list |
| ` ```lang ` | Code block |
| `> quote` | Quote block |
| Tables | Table block |

## Fidelity Preservation

Notion-specific formatting is preserved in HTML comments for round-tripping:

```markdown
<!-- notion:underline -->underlined text<!-- /notion:underline -->
<!-- notion:color=red -->colored text<!-- /notion:color -->
```

## Development

```bash
# Run tests
mix test

# Build escript
mix escript.build

# Install locally
mix escript.install
```

## License

MIT
