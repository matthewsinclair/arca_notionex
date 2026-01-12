defmodule ArcaNotionex.LinkMapTest do
  use ExUnit.Case, async: true

  alias ArcaNotionex.LinkMap

  @test_dir "test/fixtures/link_map_test"

  setup do
    # Create temp directory with test files
    File.mkdir_p!(@test_dir)

    on_exit(fn ->
      File.rm_rf!(@test_dir)
    end)

    :ok
  end

  describe "build/1" do
    test "builds bidirectional map from files with notion_id" do
      # Create test files with frontmatter
      File.write!(Path.join(@test_dir, "overview.md"), """
      ---
      title: Overview
      notion_id: abc123
      ---
      # Overview content
      """)

      File.write!(Path.join(@test_dir, "guide.md"), """
      ---
      title: Guide
      notion_id: def456
      ---
      # Guide content
      """)

      {:ok, link_map} = LinkMap.build(@test_dir)

      assert LinkMap.path_to_notion_id(link_map, "overview.md") == "abc123"
      assert LinkMap.path_to_notion_id(link_map, "guide.md") == "def456"
      assert LinkMap.notion_id_to_path(link_map, "abc123") == "overview.md"
      assert LinkMap.notion_id_to_path(link_map, "def456") == "guide.md"
    end

    test "ignores files without notion_id" do
      File.write!(Path.join(@test_dir, "with_id.md"), """
      ---
      title: Has ID
      notion_id: abc123
      ---
      Content
      """)

      File.write!(Path.join(@test_dir, "without_id.md"), """
      ---
      title: No ID
      ---
      Content
      """)

      {:ok, link_map} = LinkMap.build(@test_dir)

      assert LinkMap.path_to_notion_id(link_map, "with_id.md") == "abc123"
      assert LinkMap.path_to_notion_id(link_map, "without_id.md") == nil
    end

    test "handles nested directories" do
      File.mkdir_p!(Path.join(@test_dir, "docs/api"))

      File.write!(Path.join(@test_dir, "docs/intro.md"), """
      ---
      title: Intro
      notion_id: doc-intro
      ---
      Intro
      """)

      File.write!(Path.join(@test_dir, "docs/api/endpoints.md"), """
      ---
      title: Endpoints
      notion_id: api-endpoints
      ---
      Endpoints
      """)

      {:ok, link_map} = LinkMap.build(@test_dir)

      assert LinkMap.path_to_notion_id(link_map, "docs/intro.md") == "doc-intro"
      assert LinkMap.path_to_notion_id(link_map, "docs/api/endpoints.md") == "api-endpoints"
    end

    test "returns error for non-existent directory" do
      assert {:error, :not_found, _} = LinkMap.build("/nonexistent/path")
    end
  end

  describe "empty/0" do
    test "returns empty map" do
      link_map = LinkMap.empty()

      assert LinkMap.path_to_notion_id(link_map, "any.md") == nil
      assert LinkMap.notion_id_to_path(link_map, "any-id") == nil
    end
  end

  describe "resolve_link/3 forward direction" do
    setup do
      File.write!(Path.join(@test_dir, "overview.md"), """
      ---
      title: Overview
      notion_id: abc123
      ---
      """)

      File.write!(Path.join(@test_dir, "guide.md"), """
      ---
      title: Guide
      notion_id: def456
      ---
      """)

      {:ok, link_map} = LinkMap.build(@test_dir)
      {:ok, link_map: link_map}
    end

    test "resolves internal .md links to Notion URLs", %{link_map: link_map} do
      result = LinkMap.resolve_link(link_map, "overview.md", direction: :forward)
      assert result == "https://notion.so/abc123"
    end

    test "preserves anchors in resolved links", %{link_map: link_map} do
      result = LinkMap.resolve_link(link_map, "overview.md#section", direction: :forward)
      assert result == "https://notion.so/abc123#section"
    end

    test "returns original href for unresolved internal links", %{link_map: link_map} do
      result = LinkMap.resolve_link(link_map, "nonexistent.md", direction: :forward)
      assert result == "nonexistent.md"
    end

    test "preserves external links", %{link_map: link_map} do
      result = LinkMap.resolve_link(link_map, "https://example.com", direction: :forward)
      assert result == "https://example.com"
    end

    test "preserves anchor-only links", %{link_map: link_map} do
      result = LinkMap.resolve_link(link_map, "#section", direction: :forward)
      assert result == "#section"
    end

    test "normalizes path case", %{link_map: link_map} do
      result = LinkMap.resolve_link(link_map, "OVERVIEW.MD", direction: :forward)
      assert result == "https://notion.so/abc123"
    end

    test "strips leading ./ from paths", %{link_map: link_map} do
      result = LinkMap.resolve_link(link_map, "./overview.md", direction: :forward)
      assert result == "https://notion.so/abc123"
    end
  end

  describe "resolve_link/3 reverse direction" do
    setup do
      File.write!(Path.join(@test_dir, "overview.md"), """
      ---
      title: Overview
      notion_id: abc123
      ---
      """)

      {:ok, link_map} = LinkMap.build(@test_dir)
      {:ok, link_map: link_map}
    end

    test "resolves Notion URLs to local paths", %{link_map: link_map} do
      result = LinkMap.resolve_link(link_map, "https://notion.so/abc123", direction: :reverse)
      assert result == "overview.md"
    end

    test "handles www.notion.so URLs", %{link_map: link_map} do
      result = LinkMap.resolve_link(link_map, "https://www.notion.so/abc123", direction: :reverse)
      assert result == "overview.md"
    end

    test "preserves anchors in reverse resolution", %{link_map: link_map} do
      result =
        LinkMap.resolve_link(link_map, "https://notion.so/abc123#section", direction: :reverse)

      assert result == "overview.md#section"
    end

    test "returns original URL for unknown Notion pages", %{link_map: link_map} do
      result = LinkMap.resolve_link(link_map, "https://notion.so/unknown", direction: :reverse)
      assert result == "https://notion.so/unknown"
    end

    test "preserves non-Notion URLs", %{link_map: link_map} do
      result = LinkMap.resolve_link(link_map, "https://example.com", direction: :reverse)
      assert result == "https://example.com"
    end
  end

  describe "resolve_link/3 with current_file context" do
    setup do
      File.mkdir_p!(Path.join(@test_dir, "docs"))

      File.write!(Path.join(@test_dir, "root.md"), """
      ---
      title: Root
      notion_id: root-id
      ---
      """)

      File.write!(Path.join(@test_dir, "docs/child.md"), """
      ---
      title: Child
      notion_id: child-id
      ---
      """)

      {:ok, link_map} = LinkMap.build(@test_dir)
      {:ok, link_map: link_map}
    end

    test "resolves relative paths from current file", %{link_map: link_map} do
      # From docs/child.md linking to ../root.md
      result =
        LinkMap.resolve_link(link_map, "../root.md",
          direction: :forward,
          current_file: "docs/child.md"
        )

      # Hyphens are stripped from notion_id in URLs
      assert result == "https://notion.so/rootid"
    end
  end

  describe "resolve_for_notion/3" do
    setup do
      # Create nested directory structure like prototypes/storyfield/index.md
      File.mkdir_p!(Path.join(@test_dir, "prototypes/storyfield"))
      File.mkdir_p!(Path.join(@test_dir, "prototypes/frontdesk"))

      File.write!(Path.join(@test_dir, "prototypes/index.md"), """
      ---
      title: Prototypes
      notion_id: proto-parent-id
      ---
      # Prototypes
      """)

      File.write!(Path.join(@test_dir, "prototypes/storyfield/index.md"), """
      ---
      title: Storyfield
      notion_id: storyfield-id
      ---
      # Storyfield
      """)

      File.write!(Path.join(@test_dir, "prototypes/frontdesk/index.md"), """
      ---
      title: Frontdesk
      notion_id: frontdesk-id
      ---
      # Frontdesk
      """)

      {:ok, link_map} = LinkMap.build(@test_dir)
      {:ok, link_map: link_map}
    end

    test "resolves child index.md link to page mention", %{link_map: link_map} do
      # From prototypes/index.md linking to storyfield/index.md
      result =
        LinkMap.resolve_for_notion(
          link_map,
          "storyfield/index.md",
          current_file: "prototypes/index.md"
        )

      assert result == {:page_mention, "storyfield-id"}
    end

    test "resolves child index.md with ./ prefix", %{link_map: link_map} do
      result =
        LinkMap.resolve_for_notion(
          link_map,
          "./storyfield/index.md",
          current_file: "prototypes/index.md"
        )

      assert result == {:page_mention, "storyfield-id"}
    end

    test "returns link tuple for external URLs", %{link_map: link_map} do
      result =
        LinkMap.resolve_for_notion(
          link_map,
          "https://example.com",
          current_file: "prototypes/index.md"
        )

      assert result == {:link, "https://example.com"}
    end

    test "returns link tuple for anchor-only links", %{link_map: link_map} do
      result =
        LinkMap.resolve_for_notion(
          link_map,
          "#section",
          current_file: "prototypes/index.md"
        )

      assert result == {:link, "#section"}
    end

    test "returns link tuple for unresolved internal links", %{link_map: link_map} do
      result =
        LinkMap.resolve_for_notion(
          link_map,
          "nonexistent/index.md",
          current_file: "prototypes/index.md"
        )

      assert result == {:link, "nonexistent/index.md"}
    end
  end

  describe "is_child_link?/2" do
    test "detects link to child directory" do
      # From parent/index.md to parent/child/index.md
      assert LinkMap.is_child_link?("child/index.md", "parent/index.md")
    end

    test "detects link to child directory with ./ prefix" do
      assert LinkMap.is_child_link?("./child/index.md", "parent/index.md")
    end

    test "detects link to nested child directory" do
      # From parent/index.md to parent/child/grandchild/index.md
      assert LinkMap.is_child_link?("child/grandchild/index.md", "parent/index.md")
    end

    test "does not flag sibling file links" do
      # sibling.md is in the same directory, not a child
      refute LinkMap.is_child_link?("sibling.md", "parent/index.md")
    end

    test "does not flag parent directory links" do
      # ../other.md is in parent directory
      refute LinkMap.is_child_link?("../other.md", "parent/child/index.md")
    end

    test "does not flag same-level directory links" do
      # ../sibling/index.md is a sibling directory, not child
      refute LinkMap.is_child_link?("../sibling/index.md", "parent/child/index.md")
    end

    test "handles root level current file" do
      # From root index.md to child directory
      assert LinkMap.is_child_link?("child/index.md", "index.md")
    end

    test "does not flag anchor-only links as child" do
      refute LinkMap.is_child_link?("#section", "parent/index.md")
    end

    test "handles link with anchor to child" do
      assert LinkMap.is_child_link?("child/index.md#section", "parent/index.md")
    end

    test "does not flag external http URLs as child" do
      refute LinkMap.is_child_link?("http://example.com", "parent/index.md")
    end

    test "does not flag external https URLs as child" do
      refute LinkMap.is_child_link?("https://example.com/page", "parent/index.md")
    end
  end
end
