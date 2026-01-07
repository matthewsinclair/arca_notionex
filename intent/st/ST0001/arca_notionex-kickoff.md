# Kickoff Prompt: arca_notionex

**Purpose**: This document provides complete context for building `arca_notionex`, a standalone Elixir CLI utility for syncing markdown files to Notion.

**Target**: New Claude instance working in `../../Arca/arca_notionex/`

---

## Project Overview

### What is arca_notionex?

An Elixir CLI tool that syncs markdown files to Notion pages. It provides:

1. **Audit command**: Rich tabular comparison of local markdown vs Notion state
2. **Sync command**: Push markdown content to Notion pages

### Why does it exist?

**Use case**: The `a3-content` project (located at `../A3/a3-content/`) contains 65+ markdown documentation files that need to be published to Notion. The content philosophy is:

- **Markdown is source of truth** - Engineers write in markdown, it lives in git
- **Notion is the navigation layer** - Non-engineers read from Notion
- **One-way sync** - Markdown pushes to Notion (never pull from Notion)

### Where does it live?

This is a standalone utility in the Arca ecosystem:

- Location: `../../Arca/arca_notionex/`
- Will be published to hex.pm as `arca_notionex`
- Uses `arca_cli` for CLI framework

---

## Technical Design

### Core Strategy

1. Parse markdown to AST using `earmark_parser`
2. Transform AST to Notion blocks via `ArcaNotionex.AstToBlocks`
3. Push to Notion API using `Req` HTTP client
4. Track page IDs in markdown frontmatter

### Key Design Decisions

| Decision        | Choice                  | Rationale                                              |
|-----------------|-------------------------|--------------------------------------------------------|
| Language        | Pure Elixir             | Consistent with A3 stack, no Node.js dependency        |
| Markdown parser | Earmark                 | Standard Elixir markdown library                       |
| HTTP client     | Req                     | Modern, composable, good error handling                |
| CLI framework   | Arca.Cli                | Existing pattern used in Laksa                         |
| Sync strategy   | Replace (not merge)     | Markdown is source of truth, simplifies implementation |
| Page identity   | Frontmatter `notion_id` | Self-documenting, travels with file, works with git    |

### Notion API Constraints

| Constraint            | Handling                                     |
|-----------------------|----------------------------------------------|
| 3 requests/sec        | `:timer.sleep(334)` between requests         |
| 100 blocks/request    | Chunk blocks, multiple `append_blocks` calls |
| 2000 chars/text block | Split long paragraphs                        |

---

## Arca.Cli Pattern Reference

**IMPORTANT**: Study these files in Laksa to understand the Arca.Cli patterns:

### Configurator (Command Registry)

```
../Laksa/laksa-web/lib/laksa/repl/configurator.ex
```

- Uses `Arca.Cli.Configurator.BaseConfigurator`
- Defines all commands in config block
- Sets metadata: author, about, version

### Command Implementation

```
../Laksa/laksa-web/lib/laksa/repl/commands/*.ex
```

Key patterns:

- Use `Arca.Cli.Command.BaseCommand`
- Config block defines: name, about, args, flags, options
- `handle/3` receives (args, settings, optimus)
- Use `Arca.Cli.Ctx` for building output

Example command structure:

```elixir
defmodule ArcaNotionex.Commands.NotionexAuditCommand do
  use Arca.Cli.Command.BaseCommand
  alias Arca.Cli.Ctx

  config :"notionex.audit",
    name: "notionex.audit",
    about: "Compare local markdown files against Notion pages",
    args: [],
    flags: [],
    options: [
      path: [long: "--path", parser: :string, required: true],
      status: [long: "--status", parser: :string, required: false]
    ]

  @impl true
  def handle(args, settings, _optimus) do
    ctx = Ctx.new(args, settings)
    # Implementation
  end
end
```

### Mix Task Bridge

```
../Laksa/laksa-web/lib/mix/tasks/laksa_cli.ex
```

- Sets `REPL_MODE=true` before config loads
- Uses `@requirements ["app.config"]`
- Calls `Arca.Cli.main(args)`

### Shell Scripts

```
../Laksa/laksa-web/scripts/cli      # Direct CLI execution
../Laksa/laksa-web/scripts/repl     # Interactive with rlwrap
../Laksa/laksa-web/scripts/mix      # Mix wrapper
../Laksa/laksa-web/scripts/completions/completions.txt  # Tab completion
```

---

## Project Structure

```
arca_notionex/
├── mix.exs
├── README.md
├── CLAUDE.md
├── lib/
│   ├── arca_notionex.ex                    # Public API
│   ├── arca_notionex/
│   │   ├── configurator.ex                 # Arca.Cli command registry
│   │   ├── ast_to_blocks.ex                # Earmark AST -> Notion blocks
│   │   ├── client.ex                       # Notion API wrapper (Req)
│   │   ├── sync.ex                         # Sync orchestration
│   │   ├── frontmatter.ex                  # YAML parsing
│   │   └── audit.ex                        # Audit logic
│   ├── arca_notionex/commands/
│   │   ├── notionex_command.ex             # Namespace/help
│   │   ├── notionex_audit_command.ex       # Audit command
│   │   └── notionex_sync_command.ex        # Sync command
│   └── mix/tasks/
│       └── notionex_cli.ex                 # Mix task bridge
├── scripts/
│   ├── cli
│   ├── repl
│   ├── mix
│   └── completions/
│       └── completions.txt
├── test/
│   ├── ast_to_blocks_test.exs
│   ├── frontmatter_test.exs
│   └── test_helper.exs
└── config/
    └── config.exs
```

---

## Command Interface

### notionex.audit

**Purpose**: Show rich tabular comparison of local markdown files vs Notion pages

```bash
# Basic usage
scripts/cli notionex.audit --path ../A3/a3-content/a3-engineering

# Filter by status
scripts/cli notionex.audit --path ../A3/a3-content/a3-engineering --status stale
scripts/cli notionex.audit --path ../A3/a3-content/a3-engineering --status local-only
```

**Expected output**:

```
┌────────────────────────────┬─────────────┬──────────────┬────────────┐
│ File                       │ Local       │ Notion       │ Status     │
├────────────────────────────┼─────────────┼──────────────┼────────────┤
│ overview.md                │ ✓ (2h ago)  │ ✓ abc123     │ synced     │
│ team/hiring.md             │ ✓ (5m ago)  │ ✓ def456     │ stale      │
│ architecture/design.md     │ ✓ (1d ago)  │ ✗            │ local-only │
│ [orphan page]              │ ✗           │ ✓ ghi789     │ notion-only│
└────────────────────────────┴─────────────┴──────────────┴────────────┘

Summary: 45 synced, 3 stale, 12 local-only, 2 notion-only
```

**Status definitions**:

- `synced` - Local file has notion_id in frontmatter, page exists (content may differ)
- `stale` - Local file modified after last sync (track via frontmatter timestamp)
- `local-only` - Local file exists but no notion_id (needs initial sync)
- `notion-only` - Notion page exists but no corresponding local file (orphan)

### notionex.sync

**Purpose**: Push markdown content to Notion pages

```bash
# Sync all files in directory
scripts/cli notionex.sync --path ../A3/a3-content/a3-engineering

# Dry run (preview only)
scripts/cli notionex.sync --path ../A3/a3-content/a3-engineering --dry-run

# Sync only stale files
scripts/cli notionex.sync --path ../A3/a3-content/a3-engineering --only stale

# Sync only local-only files (new pages)
scripts/cli notionex.sync --path ../A3/a3-content/a3-engineering --only local-only
```

**Expected output**:

```
Syncing 15 files to Notion...

  ✓ overview.md -> abc123 (updated)
  ✓ team/hiring.md -> def456 (updated)
  ✓ architecture/design.md -> NEW xyz789 (created)
  ...

Done: 12 updated, 3 created, 0 errors
```

---

## Core Module Specifications

### ArcaNotionex.AstToBlocks

Transform Earmark AST to Notion block format. Port logic from [Martian](https://github.com/tryfabric/martian).

**Earmark AST format**:

```elixir
{"h1", [], ["Hello World"], %{}}
{"p", [], ["Some text with ", {"strong", [], ["bold"], %{}}, " words"], %{}}
```

**Notion block format**:

```elixir
%{
  "type" => "heading_1",
  "heading_1" => %{
    "rich_text" => [%{"type" => "text", "text" => %{"content" => "Hello World"}}]
  }
}
```

**Conversion table**:

| Earmark          | Notion                                 |
|------------------|----------------------------------------|
| `h1`, `h2`, `h3` | `heading_1`, `heading_2`, `heading_3`  |
| `h4`, `h5`, `h6` | `heading_3` (Notion only has 3 levels) |
| `p`              | `paragraph`                            |
| `ul > li`        | `bulleted_list_item`                   |
| `ol > li`        | `numbered_list_item`                   |
| `pre > code`     | `code` (with language)                 |
| `blockquote`     | `quote`                                |
| `table`          | `table`                                |
| `a`              | Rich text with link annotation         |
| `strong`         | Rich text with `bold: true`            |
| `em`             | Rich text with `italic: true`          |
| `code` (inline)  | Rich text with `code: true`            |

### ArcaNotionex.Client

Notion API wrapper using Req.

**Key functions**:

```elixir
# Create a new page under parent
create_page(parent_id, title, blocks)

# Update page content (replace all blocks)
update_page(page_id, blocks)

# Get page metadata
get_page(page_id)

# List child pages under parent
list_children(parent_id)
```

**Configuration** (via environment or config):

```elixir
config :arca_notionex,
  notion_token: System.get_env("NOTION_TOKEN"),
  parent_page_id: System.get_env("NOTION_PARENT_PAGE_ID")
```

### ArcaNotionex.Frontmatter

Parse and update YAML frontmatter in markdown files.

**Example frontmatter**:

```yaml
---
notion_id: abc123-def456-ghi789
notion_synced_at: 2024-01-07T10:30:00Z
---
# Page Title
```

**Key functions**:

```elixir
# Parse frontmatter from markdown content
parse(markdown_content) :: {:ok, %{frontmatter: map, content: string}}

# Add/update notion_id in file
update_notion_id(file_path, notion_id)

# Update sync timestamp
update_synced_at(file_path)
```

### ArcaNotionex.Sync

Orchestrate the sync process.

**Key functions**:

```elixir
# Scan directory and return audit info
audit(path, opts \\ [])

# Sync files to Notion
sync(path, opts \\ [])
```

**Options**:

- `:dry_run` - Preview only, don't modify
- `:only` - Filter by status (`:stale`, `:local_only`)
- `:verbose` - Extra logging

---

## Dependencies

```elixir
# mix.exs
defp deps do
  [
    {:arca_cli, "~> 0.1"},           # CLI framework
    {:earmark_parser, "~> 1.4"},     # Markdown to AST
    {:req, "~> 0.4"},                # HTTP client
    {:yaml_elixir, "~> 2.9"},        # YAML frontmatter parsing
    {:table_rex, "~> 4.0"}           # Nice table output
  ]
end
```

---

## User Preferences

**CRITICAL - Follow these rules**:

1. **No JavaScript** - Pure Elixir implementation
2. **No `iex`** - Use `mix run` or tests for execution
3. **No backwards compatibility code** unless explicitly requested
4. **Use Intent framework** for work tracking if needed

---

## External References

Study these before implementing:

1. **[Martian](https://github.com/tryfabric/martian)** - JavaScript library to port (markdown → Notion blocks)
2. **[Notion API docs](https://developers.notion.com/)** - Block types, rate limits, authentication
3. **[Earmark](https://hexdocs.pm/earmark/)** - Markdown parser AST format

---

## Implementation Order

Suggested phases:

1. **Scaffold** - Mix project, deps, basic structure, scripts
2. **Frontmatter** - YAML parsing (simple, testable in isolation)
3. **AstToBlocks** - Core conversion with comprehensive tests
4. **Client** - Notion API wrapper with rate limiting
5. **Audit** - Directory scanning, status comparison
6. **Sync** - Orchestration, file updates
7. **Commands** - Wire up Arca.Cli commands
8. **Polish** - Error messages, edge cases

---

## Test Data

The `a3-content` project has 65 markdown files you can test against:

```
../A3/a3-content/
├── a3-home/           # 6 files
├── a3-engineering/    # 25 files
└── a3-product/        # 14 files
```

All have `<!-- TODO -->` markers (placeholder content), good for testing sync.

---

## Getting Started

```bash
cd ../../Arca/arca_notionex

# Create mix project if not exists
mix new . --module ArcaNotionex

# Add dependencies to mix.exs
# Create directory structure
# Copy script templates from Laksa

# Run tests
mix test

# Try CLI
scripts/cli notionex.audit --path ../A3/a3-content/a3-engineering
```

---

## Questions?

If anything is unclear, ask! Better to clarify upfront than build the wrong thing.
