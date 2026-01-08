defmodule ArcaNotionex.Conflict do
  @moduledoc """
  Conflict detection and resolution for sync operations.

  Detects conflicts between local markdown files and Notion pages by comparing:
  - `notion_synced_at` from local file frontmatter (last successful sync)
  - `last_edited_time` from Notion API response
  - Local file modification time

  ## Resolution Strategies

  - `:manual` (default) - Auto-pull if only Notion changed; flag conflicts for user decision
  - `:local_wins` - Skip all pulls, preserve local files
  - `:notion_wins` - Overwrite local files with Notion content
  - `:newest_wins` - Compare timestamps, most recent modification wins

  ## Example

      # Detect conflict status
      status = Conflict.detect(local_file, notion_page)
      #=> :both_modified | :notion_newer | :local_newer | :no_conflict | :new_page

      # Resolve based on strategy
      action = Conflict.resolve(:manual, status, local_file, notion_page)
      #=> {:skip, reason} | {:update, notion_page} | {:conflict, entry}

  """

  alias ArcaNotionex.Schemas.ConflictEntry

  @type conflict_status :: :no_conflict | :notion_newer | :local_newer | :both_modified | :new_page
  @type resolution_strategy :: :manual | :local_wins | :notion_wins | :newest_wins

  @type local_file :: %{
          path: String.t(),
          notion_synced_at: DateTime.t() | nil,
          mtime: DateTime.t() | nil
        }

  @type notion_page :: %{
          id: String.t(),
          last_edited_time: DateTime.t()
        }

  @type resolution :: {:skip, String.t()} | {:update, notion_page()} | {:conflict, ConflictEntry.t()}

  @doc """
  Detects conflict status between a local file and Notion page.

  Returns:
  - `:no_conflict` - Neither modified since last sync
  - `:notion_newer` - Only Notion page modified
  - `:local_newer` - Only local file modified
  - `:both_modified` - Both modified since last sync
  - `:new_page` - Page exists in Notion but no local file
  """
  @spec detect(local_file() | nil, notion_page()) :: conflict_status()
  def detect(nil, _notion_page) do
    :new_page
  end

  def detect(%{notion_synced_at: nil}, _notion_page) do
    # File has no sync timestamp - treat as potentially conflicting
    :both_modified
  end

  def detect(local_file, notion_page) do
    synced_at = local_file.notion_synced_at
    notion_edited = notion_page.last_edited_time
    local_mtime = local_file.mtime

    notion_changed = compare_times(notion_edited, synced_at) == :gt
    local_changed = local_mtime && compare_times(local_mtime, synced_at) == :gt

    cond do
      notion_changed and local_changed -> :both_modified
      notion_changed -> :notion_newer
      local_changed -> :local_newer
      true -> :no_conflict
    end
  end

  @doc """
  Resolves a conflict based on the specified strategy.

  Returns:
  - `{:skip, reason}` - Skip this file (preserve local)
  - `{:update, notion_page}` - Update local file with Notion content
  - `{:conflict, entry}` - Conflict needs manual resolution
  """
  @spec resolve(resolution_strategy(), conflict_status(), local_file() | nil, notion_page()) :: resolution()
  def resolve(strategy, status, local_file, notion_page)

  # :local_wins - Always skip pulls
  def resolve(:local_wins, _status, _local_file, _notion_page) do
    {:skip, "Local file preserved (--local-wins)"}
  end

  # :notion_wins - Always update from Notion
  def resolve(:notion_wins, :new_page, _local_file, notion_page) do
    {:update, notion_page}
  end

  def resolve(:notion_wins, _status, _local_file, notion_page) do
    {:update, notion_page}
  end

  # :newest_wins - Compare timestamps
  def resolve(:newest_wins, :new_page, _local_file, notion_page) do
    {:update, notion_page}
  end

  def resolve(:newest_wins, :notion_newer, _local_file, notion_page) do
    {:update, notion_page}
  end

  def resolve(:newest_wins, :local_newer, _local_file, _notion_page) do
    {:skip, "Local file is newer"}
  end

  def resolve(:newest_wins, :both_modified, local_file, notion_page) do
    local_mtime = local_file.mtime
    notion_edited = notion_page.last_edited_time

    if compare_times(notion_edited, local_mtime) == :gt do
      {:update, notion_page}
    else
      {:skip, "Local file is newer or same age"}
    end
  end

  def resolve(:newest_wins, :no_conflict, _local_file, _notion_page) do
    {:skip, "No changes detected"}
  end

  # :manual - Auto-pull safe cases, flag conflicts
  def resolve(:manual, :new_page, _local_file, notion_page) do
    {:update, notion_page}
  end

  def resolve(:manual, :notion_newer, _local_file, notion_page) do
    # Safe to pull - only Notion changed
    {:update, notion_page}
  end

  def resolve(:manual, :local_newer, local_file, notion_page) do
    # Local changes would be overwritten - flag as conflict
    entry = build_conflict_entry(local_file, notion_page, :local_newer)
    {:conflict, entry}
  end

  def resolve(:manual, :both_modified, local_file, notion_page) do
    entry = build_conflict_entry(local_file, notion_page, :both_modified)
    {:conflict, entry}
  end

  def resolve(:manual, :no_conflict, _local_file, _notion_page) do
    {:skip, "No changes detected"}
  end

  # Helpers

  defp compare_times(nil, _), do: :lt
  defp compare_times(_, nil), do: :gt

  defp compare_times(time1, time2) do
    DateTime.compare(time1, time2)
  end

  defp build_conflict_entry(local_file, notion_page, conflict_type) do
    ConflictEntry.new(
      local_file.path,
      notion_page.id,
      conflict_type,
      local_modified_at: local_file.mtime,
      notion_modified_at: notion_page.last_edited_time
    )
  end
end
