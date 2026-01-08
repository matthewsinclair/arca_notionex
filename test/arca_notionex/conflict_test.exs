defmodule ArcaNotionex.ConflictTest do
  use ExUnit.Case, async: true

  alias ArcaNotionex.Conflict
  alias ArcaNotionex.Schemas.ConflictEntry

  # Test fixtures
  @now DateTime.utc_now()
  @one_hour_ago DateTime.add(@now, -3600, :second)
  @two_hours_ago DateTime.add(@now, -7200, :second)

  defp local_file(opts \\ []) do
    %{
      path: Keyword.get(opts, :path, "test.md"),
      notion_synced_at: Keyword.get(opts, :synced_at, @two_hours_ago),
      mtime: Keyword.get(opts, :mtime, @two_hours_ago)
    }
  end

  defp notion_page(opts \\ []) do
    %{
      id: Keyword.get(opts, :id, "abc123"),
      last_edited_time: Keyword.get(opts, :edited_at, @two_hours_ago)
    }
  end

  describe "detect/2" do
    test "returns :new_page when local file is nil" do
      assert Conflict.detect(nil, notion_page()) == :new_page
    end

    test "returns :both_modified when synced_at is nil" do
      file = local_file(synced_at: nil)
      assert Conflict.detect(file, notion_page()) == :both_modified
    end

    test "returns :no_conflict when neither changed" do
      file = local_file(synced_at: @two_hours_ago, mtime: @two_hours_ago)
      page = notion_page(edited_at: @two_hours_ago)

      assert Conflict.detect(file, page) == :no_conflict
    end

    test "returns :notion_newer when only Notion changed" do
      file = local_file(synced_at: @two_hours_ago, mtime: @two_hours_ago)
      page = notion_page(edited_at: @one_hour_ago)

      assert Conflict.detect(file, page) == :notion_newer
    end

    test "returns :local_newer when only local file changed" do
      file = local_file(synced_at: @two_hours_ago, mtime: @one_hour_ago)
      page = notion_page(edited_at: @two_hours_ago)

      assert Conflict.detect(file, page) == :local_newer
    end

    test "returns :both_modified when both changed" do
      file = local_file(synced_at: @two_hours_ago, mtime: @one_hour_ago)
      page = notion_page(edited_at: @now)

      assert Conflict.detect(file, page) == :both_modified
    end
  end

  describe "resolve/4 with :local_wins" do
    test "always skips" do
      file = local_file()
      page = notion_page()

      assert {:skip, _} = Conflict.resolve(:local_wins, :notion_newer, file, page)
      assert {:skip, _} = Conflict.resolve(:local_wins, :both_modified, file, page)
      assert {:skip, _} = Conflict.resolve(:local_wins, :new_page, nil, page)
    end
  end

  describe "resolve/4 with :notion_wins" do
    test "always updates from Notion" do
      file = local_file()
      page = notion_page()

      assert {:update, ^page} = Conflict.resolve(:notion_wins, :local_newer, file, page)
      assert {:update, ^page} = Conflict.resolve(:notion_wins, :both_modified, file, page)
      assert {:update, ^page} = Conflict.resolve(:notion_wins, :no_conflict, file, page)
      assert {:update, ^page} = Conflict.resolve(:notion_wins, :new_page, nil, page)
    end
  end

  describe "resolve/4 with :newest_wins" do
    test "updates when Notion is newer" do
      file = local_file()
      page = notion_page()

      assert {:update, ^page} = Conflict.resolve(:newest_wins, :notion_newer, file, page)
    end

    test "skips when local is newer" do
      file = local_file()
      page = notion_page()

      assert {:skip, _} = Conflict.resolve(:newest_wins, :local_newer, file, page)
    end

    test "compares timestamps when both modified" do
      # Notion is newer
      file = local_file(mtime: @one_hour_ago)
      page = notion_page(edited_at: @now)

      assert {:update, ^page} = Conflict.resolve(:newest_wins, :both_modified, file, page)

      # Local is newer
      file2 = local_file(mtime: @now)
      page2 = notion_page(edited_at: @one_hour_ago)

      assert {:skip, _} = Conflict.resolve(:newest_wins, :both_modified, file2, page2)
    end

    test "updates for new pages" do
      page = notion_page()

      assert {:update, ^page} = Conflict.resolve(:newest_wins, :new_page, nil, page)
    end

    test "skips when no conflict" do
      file = local_file()
      page = notion_page()

      assert {:skip, _} = Conflict.resolve(:newest_wins, :no_conflict, file, page)
    end
  end

  describe "resolve/4 with :manual" do
    test "updates for new pages" do
      page = notion_page()

      assert {:update, ^page} = Conflict.resolve(:manual, :new_page, nil, page)
    end

    test "updates when only Notion changed (safe)" do
      file = local_file()
      page = notion_page()

      assert {:update, ^page} = Conflict.resolve(:manual, :notion_newer, file, page)
    end

    test "returns conflict when local is newer" do
      file = local_file(path: "docs/test.md")
      page = notion_page(id: "page123")

      assert {:conflict, %ConflictEntry{} = entry} =
               Conflict.resolve(:manual, :local_newer, file, page)

      assert entry.file == "docs/test.md"
      assert entry.notion_id == "page123"
      assert entry.conflict_type == :local_newer
    end

    test "returns conflict when both modified" do
      file = local_file(path: "docs/test.md", mtime: @one_hour_ago)
      page = notion_page(id: "page123", edited_at: @now)

      assert {:conflict, %ConflictEntry{} = entry} =
               Conflict.resolve(:manual, :both_modified, file, page)

      assert entry.conflict_type == :both_modified
      assert entry.local_modified_at == @one_hour_ago
      assert entry.notion_modified_at == @now
    end

    test "skips when no conflict" do
      file = local_file()
      page = notion_page()

      assert {:skip, _} = Conflict.resolve(:manual, :no_conflict, file, page)
    end
  end

  describe "ConflictEntry.format/1" do
    test "formats both_modified conflict" do
      entry = ConflictEntry.new("test.md", "abc123", :both_modified)

      assert ConflictEntry.format(entry) == "test.md - both modified since last sync"
    end

    test "formats notion_newer conflict" do
      entry = ConflictEntry.new("test.md", "abc123", :notion_newer)

      assert ConflictEntry.format(entry) == "test.md - Notion page is newer"
    end

    test "formats local_newer conflict" do
      entry = ConflictEntry.new("test.md", "abc123", :local_newer)

      assert ConflictEntry.format(entry) == "test.md - local file is newer"
    end
  end
end
