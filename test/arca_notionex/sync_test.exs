defmodule ArcaNotionex.SyncTest do
  use ExUnit.Case, async: true

  alias ArcaNotionex.Sync
  alias ArcaNotionex.Schemas.FileEntry

  @moduletag :tmp_dir

  describe "discover_files/1" do
    test "discovers markdown files in directory", %{tmp_dir: tmp_dir} do
      # Create test files
      File.write!(Path.join(tmp_dir, "file1.md"), "# File 1")
      File.write!(Path.join(tmp_dir, "file2.md"), "# File 2")

      assert {:ok, files} = Sync.discover_files(tmp_dir)
      assert length(files) == 2
      assert Enum.all?(files, &match?(%FileEntry{}, &1))
    end

    test "discovers files in nested directories", %{tmp_dir: tmp_dir} do
      # Create nested structure
      subdir = Path.join(tmp_dir, "subdir")
      File.mkdir_p!(subdir)

      File.write!(Path.join(tmp_dir, "root.md"), "# Root")
      File.write!(Path.join(subdir, "nested.md"), "# Nested")

      assert {:ok, files} = Sync.discover_files(tmp_dir)
      assert length(files) == 2

      depths = Enum.map(files, & &1.depth)
      assert 0 in depths
      assert 1 in depths
    end

    test "sorts files by depth (shallow first)", %{tmp_dir: tmp_dir} do
      # Create deeply nested structure
      deep = Path.join([tmp_dir, "a", "b", "c"])
      File.mkdir_p!(deep)

      File.write!(Path.join(tmp_dir, "root.md"), "# Root")
      File.write!(Path.join(deep, "deep.md"), "# Deep")

      assert {:ok, files} = Sync.discover_files(tmp_dir)
      assert length(files) == 2

      [first, second] = files
      assert first.depth < second.depth
    end

    test "returns error for non-directory path", %{tmp_dir: tmp_dir} do
      file_path = Path.join(tmp_dir, "not-a-dir.md")
      File.write!(file_path, "# Content")

      assert {:error, :not_a_directory, msg} = Sync.discover_files(file_path)
      assert msg =~ "not a directory"
    end

    test "returns empty list for directory with no markdown files", %{tmp_dir: tmp_dir} do
      # Create non-markdown files
      File.write!(Path.join(tmp_dir, "file.txt"), "not markdown")
      File.write!(Path.join(tmp_dir, "data.json"), "{}")

      assert {:ok, files} = Sync.discover_files(tmp_dir)
      assert files == []
    end

    test "correctly computes relative paths and parent paths", %{tmp_dir: tmp_dir} do
      # Create structure: tmp_dir/docs/arch/design.md
      arch_dir = Path.join([tmp_dir, "docs", "arch"])
      File.mkdir_p!(arch_dir)
      File.write!(Path.join(arch_dir, "design.md"), "# Design")

      assert {:ok, [file]} = Sync.discover_files(tmp_dir)
      assert file.relative_path == "docs/arch/design.md"
      assert file.parent_path == "docs/arch"
      assert file.depth == 2
    end
  end

  describe "sync_directory/2 with dry_run" do
    test "dry run returns created for new files", %{tmp_dir: tmp_dir} do
      # Create a file without notion_id (new file)
      content = """
      ---
      title: "Test Page"
      ---
      # Test

      Content here.
      """

      File.write!(Path.join(tmp_dir, "test.md"), content)

      assert {:ok, result} = Sync.sync_directory(tmp_dir, root_page_id: "fake-id", dry_run: true)
      assert result.created == ["test.md"]
      assert result.updated == []
      assert result.errors == []
    end

    test "dry run returns updated for existing synced files", %{tmp_dir: tmp_dir} do
      # Create a file with notion_id (already synced)
      content = """
      ---
      title: "Existing Page"
      notion_id: "existing-page-id"
      ---
      # Existing

      Updated content.
      """

      File.write!(Path.join(tmp_dir, "existing.md"), content)

      assert {:ok, result} = Sync.sync_directory(tmp_dir, root_page_id: "fake-id", dry_run: true)
      assert result.updated == ["existing.md"]
      assert result.created == []
      assert result.errors == []
    end

    test "dry run creates directory pages for nested files", %{tmp_dir: tmp_dir} do
      # Create nested structure
      docs_dir = Path.join(tmp_dir, "docs")
      arch_dir = Path.join(docs_dir, "architecture")
      File.mkdir_p!(arch_dir)

      content = """
      ---
      title: "Architecture Doc"
      ---
      # Architecture
      """

      File.write!(Path.join(arch_dir, "design.md"), content)

      # This should work in dry-run mode, creating fake directory page IDs
      assert {:ok, result} = Sync.sync_directory(tmp_dir, root_page_id: "root-id", dry_run: true)
      assert result.created == ["docs/architecture/design.md"]
      assert result.errors == []
    end

    test "dry run handles multiple nested directories", %{tmp_dir: tmp_dir} do
      # Create complex structure
      Path.join([tmp_dir, "a", "b", "c"]) |> File.mkdir_p!()
      Path.join([tmp_dir, "x", "y"]) |> File.mkdir_p!()

      File.write!(Path.join([tmp_dir, "root.md"]), "---\ntitle: Root\n---\n# Root")
      File.write!(Path.join([tmp_dir, "a", "b", "c", "deep.md"]), "---\ntitle: Deep\n---\n# Deep")
      File.write!(Path.join([tmp_dir, "x", "y", "other.md"]), "---\ntitle: Other\n---\n# Other")

      assert {:ok, result} = Sync.sync_directory(tmp_dir, root_page_id: "root-id", dry_run: true)

      # All files should be "created" in dry-run (no notion_id in frontmatter)
      assert length(result.created) == 3
      assert Enum.sort(result.created) == ["a/b/c/deep.md", "root.md", "x/y/other.md"]
      assert result.errors == []
    end
  end

  describe "sync_file/3 with dry_run" do
    test "returns created for file without notion_id", %{tmp_dir: tmp_dir} do
      content = """
      ---
      title: "New Page"
      ---
      # Content
      """

      file_path = Path.join(tmp_dir, "new.md")
      File.write!(file_path, content)

      assert {:ok, :created, msg} = Sync.sync_file(file_path, "parent-id", dry_run: true)
      assert msg =~ "[dry-run]"
      assert msg =~ "created"
    end

    test "returns updated for file with notion_id", %{tmp_dir: tmp_dir} do
      content = """
      ---
      title: "Existing Page"
      notion_id: "page-123"
      ---
      # Content
      """

      file_path = Path.join(tmp_dir, "existing.md")
      File.write!(file_path, content)

      assert {:ok, :updated, msg} = Sync.sync_file(file_path, "parent-id", dry_run: true)
      assert msg =~ "[dry-run]"
      assert msg =~ "updated"
    end

    test "derives title from filename when not in frontmatter", %{tmp_dir: tmp_dir} do
      content = """
      ---
      ---
      # Content without explicit title
      """

      file_path = Path.join(tmp_dir, "my-great-document.md")
      File.write!(file_path, content)

      assert {:ok, :created, msg} = Sync.sync_file(file_path, "parent-id", dry_run: true)
      # Title should be derived from filename
      assert msg =~ "My Great Document"
    end

    test "returns error for non-existent file" do
      assert {:error, :enoent} =
               Sync.sync_file("/nonexistent/path.md", "parent-id", dry_run: true)
    end

    test "returns error for malformed frontmatter", %{tmp_dir: tmp_dir} do
      content = """
      ---
      title: [unclosed bracket
      ---
      # Content
      """

      file_path = Path.join(tmp_dir, "malformed.md")
      File.write!(file_path, content)

      assert {:error, :yaml_parse_error, _} =
               Sync.sync_file(file_path, "parent-id", dry_run: true)
    end
  end

  describe "FileEntry creation" do
    test "FileEntry.new/2 computes correct properties", %{tmp_dir: tmp_dir} do
      # Create nested file
      nested = Path.join([tmp_dir, "docs", "api"])
      File.mkdir_p!(nested)
      file_path = Path.join(nested, "endpoints.md")
      File.write!(file_path, "# API")

      entry = FileEntry.new(file_path, tmp_dir)

      assert entry.path == file_path
      assert entry.relative_path == "docs/api/endpoints.md"
      assert entry.parent_path == "docs/api"
      assert entry.depth == 2
    end

    test "FileEntry.new/2 handles root-level files", %{tmp_dir: tmp_dir} do
      file_path = Path.join(tmp_dir, "readme.md")
      File.write!(file_path, "# README")

      entry = FileEntry.new(file_path, tmp_dir)

      assert entry.relative_path == "readme.md"
      assert entry.parent_path == nil
      assert entry.depth == 0
    end
  end

  describe "validate_unique_titles/2" do
    test "passes when titles are unique per directory", %{tmp_dir: tmp_dir} do
      # Create files with same name in different directories
      arch_dir = Path.join(tmp_dir, "architecture")
      dev_dir = Path.join(tmp_dir, "development")
      File.mkdir_p!(arch_dir)
      File.mkdir_p!(dev_dir)

      # Same title in different directories - should be allowed
      File.write!(Path.join(arch_dir, "index.md"), "---\ntitle: Overview\n---\n# Overview")
      File.write!(Path.join(dev_dir, "index.md"), "---\ntitle: Overview\n---\n# Overview")

      {:ok, files} = Sync.discover_files(tmp_dir)
      assert :ok = Sync.validate_unique_titles(files, tmp_dir)
    end

    test "fails when duplicate titles exist in same directory", %{tmp_dir: tmp_dir} do
      # Create two files with the same title in the same directory
      File.write!(Path.join(tmp_dir, "file1.md"), "---\ntitle: \"Same Title\"\n---\n# Content")
      File.write!(Path.join(tmp_dir, "file2.md"), "---\ntitle: \"Same Title\"\n---\n# Content")

      {:ok, files} = Sync.discover_files(tmp_dir)
      assert {:error, :duplicate_titles, msg} = Sync.validate_unique_titles(files, tmp_dir)
      assert msg =~ "Same Title"
      assert msg =~ "file1.md"
      assert msg =~ "file2.md"
    end

    test "detects duplicate titles derived from index.md files", %{tmp_dir: tmp_dir} do
      # Create a directory structure where two index.md would get same derived title
      # This shouldn't happen in normal use, but let's make sure it's caught
      subdir = Path.join(tmp_dir, "docs")
      File.mkdir_p!(subdir)

      # Both would derive to "Docs" if they were both index.md,
      # but one is index.md (derives to "Docs") and one is docs.md (derives to "Docs")
      File.write!(Path.join(subdir, "index.md"), "# Index\n")
      File.write!(Path.join(tmp_dir, "docs.md"), "# Docs\n")

      {:ok, files} = Sync.discover_files(tmp_dir)
      # subdir/index.md derives to "Docs", docs.md derives to "Docs"
      # But they're in different directories (subdir vs root), so should pass
      assert :ok = Sync.validate_unique_titles(files, tmp_dir)
    end

    test "handles smart title derivation for index.md", %{tmp_dir: tmp_dir} do
      # Create structure where index.md files get smart titles
      arch_dir = Path.join(tmp_dir, "architecture")
      File.mkdir_p!(arch_dir)

      # Both files have "Index" as content heading, but should derive different titles
      File.write!(Path.join(arch_dir, "index.md"), "# Index\n")
      File.write!(Path.join(tmp_dir, "index.md"), "# Index\n")

      {:ok, files} = Sync.discover_files(tmp_dir)
      # Root index.md -> "Index", architecture/index.md -> "Architecture"
      # They're in different directories anyway, but titles are also different
      assert :ok = Sync.validate_unique_titles(files, tmp_dir)
    end

    test "reports all duplicates in error message", %{tmp_dir: tmp_dir} do
      # Create multiple duplicate pairs
      File.write!(Path.join(tmp_dir, "a.md"), "---\ntitle: \"Title A\"\n---\n# A")
      File.write!(Path.join(tmp_dir, "b.md"), "---\ntitle: \"Title A\"\n---\n# A")
      File.write!(Path.join(tmp_dir, "c.md"), "---\ntitle: \"Title B\"\n---\n# B")
      File.write!(Path.join(tmp_dir, "d.md"), "---\ntitle: \"Title B\"\n---\n# B")

      {:ok, files} = Sync.discover_files(tmp_dir)
      assert {:error, :duplicate_titles, msg} = Sync.validate_unique_titles(files, tmp_dir)
      assert msg =~ "Title A"
      assert msg =~ "Title B"
    end
  end

  describe "sync_directory/2 title validation" do
    test "fails sync when duplicate titles detected", %{tmp_dir: tmp_dir} do
      File.write!(Path.join(tmp_dir, "file1.md"), "---\ntitle: Duplicate\n---\n# Content")
      File.write!(Path.join(tmp_dir, "file2.md"), "---\ntitle: Duplicate\n---\n# Content")

      assert {:error, :duplicate_titles, _msg} =
               Sync.sync_directory(tmp_dir, root_page_id: "fake-id", dry_run: true)
    end
  end
end
