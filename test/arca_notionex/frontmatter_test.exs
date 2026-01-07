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
end
