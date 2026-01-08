defmodule ArcaNotionex.FrontmatterTest do
  use ExUnit.Case, async: true

  alias ArcaNotionex.Frontmatter
  alias ArcaNotionex.Schemas.Frontmatter, as: FrontmatterSchema

  describe "parse/1" do
    test "parses valid frontmatter with all fields" do
      content = """
      ---
      title: "Test Page"
      notion_id: "abc123-def456"
      notion_synced_at: "2024-01-07T10:30:00Z"
      ---
      # Hello World

      Some content here.
      """

      assert {:ok, fm, body} = Frontmatter.parse(content)
      assert fm.title == "Test Page"
      assert fm.notion_id == "abc123-def456"
      assert %DateTime{} = fm.notion_synced_at
      assert body =~ "# Hello World"
    end

    test "parses frontmatter with missing optional fields" do
      content = """
      ---
      title: "Just a Title"
      ---
      Content follows.
      """

      assert {:ok, fm, body} = Frontmatter.parse(content)
      assert fm.title == "Just a Title"
      assert fm.notion_id == nil
      assert fm.notion_synced_at == nil
      assert body == "Content follows.\n"
    end

    test "handles content without frontmatter" do
      content = """
      # No Frontmatter

      Just plain markdown.
      """

      assert {:ok, fm, body} = Frontmatter.parse(content)
      assert fm.title == nil
      assert fm.notion_id == nil
      assert body == content
    end

    test "handles empty frontmatter" do
      content = """
      ---
      ---
      # Content
      """

      assert {:ok, fm, body} = Frontmatter.parse(content)
      assert fm.title == nil
      assert body =~ "# Content"
    end

    test "returns error for malformed YAML" do
      content = """
      ---
      title: [unclosed bracket
      ---
      Content
      """

      assert {:error, :yaml_parse_error, _message} = Frontmatter.parse(content)
    end

    test "handles frontmatter with extra fields (ignores them)" do
      content = """
      ---
      title: "Page"
      author: "John"
      custom_field: "value"
      ---
      Body
      """

      assert {:ok, fm, body} = Frontmatter.parse(content)
      assert fm.title == "Page"
      assert body == "Body\n"
    end
  end

  describe "serialize/1" do
    test "serializes frontmatter with all fields" do
      fm = %FrontmatterSchema{
        title: "Test",
        notion_id: "abc123",
        notion_synced_at: ~U[2024-01-07 10:30:00Z]
      }

      result = Frontmatter.serialize(fm)
      assert result =~ "---"
      assert result =~ "title: \"Test\""
      assert result =~ "notion_id: \"abc123\""
      assert result =~ "notion_synced_at:"
    end

    test "serializes frontmatter with only some fields" do
      fm = %FrontmatterSchema{title: "Only Title", notion_id: nil, notion_synced_at: nil}

      result = Frontmatter.serialize(fm)
      assert result =~ "title: \"Only Title\""
      refute result =~ "notion_id"
      refute result =~ "notion_synced_at"
    end

    test "handles special characters in title" do
      fm = %FrontmatterSchema{title: "Title with \"quotes\" and \\backslash"}

      result = Frontmatter.serialize(fm)
      assert result =~ "title:"
    end
  end

  describe "roundtrip" do
    test "parse and serialize preserves data" do
      original = """
      ---
      title: "My Page"
      notion_id: "page-123"
      ---
      # Content
      """

      assert {:ok, fm, body} = Frontmatter.parse(original)
      serialized = Frontmatter.serialize(fm)
      reconstructed = serialized <> body

      assert {:ok, fm2, body2} = Frontmatter.parse(reconstructed)
      assert fm.title == fm2.title
      assert fm.notion_id == fm2.notion_id
      assert body == body2
    end
  end

  describe "derive_title_from_path/1" do
    test "uses parent directory name for index.md in subdirectory" do
      assert Frontmatter.derive_title_from_path("docs/architecture/index.md") == "Architecture"

      assert Frontmatter.derive_title_from_path("a3-engineering/development/index.md") ==
               "Development"
    end

    test "keeps Index for root index.md" do
      assert Frontmatter.derive_title_from_path("index.md") == "Index"
    end

    test "humanizes regular filenames" do
      assert Frontmatter.derive_title_from_path("my-great-doc.md") == "My Great Doc"
      assert Frontmatter.derive_title_from_path("api_reference.md") == "Api Reference"
    end

    test "handles deeply nested index.md" do
      assert Frontmatter.derive_title_from_path("a/b/c/d/index.md") == "D"
    end

    test "handles directory names with hyphens and underscores" do
      assert Frontmatter.derive_title_from_path("my-great-section/index.md") == "My Great Section"
      assert Frontmatter.derive_title_from_path("api_docs/index.md") == "Api Docs"
    end
  end

  describe "compute_hash/1" do
    test "computes SHA-256 hash with prefix" do
      hash = Frontmatter.compute_hash("Hello world")
      assert String.starts_with?(hash, "sha256:")
      # "sha256:" (7) + 64 hex chars
      assert String.length(hash) == 71
    end

    test "same content produces same hash" do
      hash1 = Frontmatter.compute_hash("test content")
      hash2 = Frontmatter.compute_hash("test content")
      assert hash1 == hash2
    end

    test "different content produces different hash" do
      hash1 = Frontmatter.compute_hash("content a")
      hash2 = Frontmatter.compute_hash("content b")
      refute hash1 == hash2
    end
  end

  describe "content_changed?/2" do
    test "returns true when hash differs" do
      stored = Frontmatter.compute_hash("old content")
      assert Frontmatter.content_changed?("new content", stored)
    end

    test "returns false when hash matches" do
      content = "same content"
      stored = Frontmatter.compute_hash(content)
      refute Frontmatter.content_changed?(content, stored)
    end

    test "returns true when stored hash is nil (first sync)" do
      assert Frontmatter.content_changed?("any content", nil)
    end
  end

  describe "ensure_frontmatter/1" do
    @moduletag :tmp_dir

    test "derives smart title for index.md", %{tmp_dir: tmp_dir} do
      # Create nested directory
      arch_dir = Path.join(tmp_dir, "architecture")
      File.mkdir_p!(arch_dir)

      content = """
      # Index

      Some content here.
      """

      file_path = Path.join(arch_dir, "index.md")
      File.write!(file_path, content)

      assert :ok = Frontmatter.ensure_frontmatter(file_path)

      # Re-read and verify title was set to parent dir name
      {:ok, updated_content} = File.read(file_path)
      assert {:ok, fm, _body} = Frontmatter.parse(updated_content)
      assert fm.title == "Architecture"
    end

    test "keeps meaningful titles that are not Index", %{tmp_dir: tmp_dir} do
      content = """
      ---
      title: "My Custom Title"
      ---
      # Some Content
      """

      file_path = Path.join(tmp_dir, "test.md")
      File.write!(file_path, content)

      assert {:already_has_title, "My Custom Title"} = Frontmatter.ensure_frontmatter(file_path)
    end

    test "overrides generic Index title with smart derivation", %{tmp_dir: tmp_dir} do
      # Create nested directory
      docs_dir = Path.join(tmp_dir, "documentation")
      File.mkdir_p!(docs_dir)

      content = """
      ---
      title: "Index"
      ---
      # Index
      """

      file_path = Path.join(docs_dir, "index.md")
      File.write!(file_path, content)

      # Should update because "Index" is generic
      assert :ok = Frontmatter.ensure_frontmatter(file_path)

      # Verify title was changed
      {:ok, updated_content} = File.read(file_path)
      assert {:ok, fm, _body} = Frontmatter.parse(updated_content)
      assert fm.title == "Documentation"
    end
  end
end
