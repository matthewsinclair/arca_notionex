# arca_notionex Project Guidelines

This is an Intent v2.3.3 project.

## Project Structure

- `intent/` - Project artifacts (steel threads, docs, work tracking)
- `backlog/` - Task management (if using Backlog.md)
- `.intent/` - Configuration and metadata

## Steel Threads

Steel threads are organized as directories under `intent/st/`:
- Each steel thread has its own directory (e.g., ST0001/)
- Minimum required file is `info.md` with metadata
- Optional files: design.md, impl.md, tasks.md

## Commands

- `intent st new "Title"` - Create a new steel thread
- `intent st list` - List all steel threads
- `intent st show <id>` - Show steel thread details
- `intent doctor` - Check configuration
- `intent help` - Get help

## Author

matts
