defmodule ArcaNotionex.AstToBlocksTest do
  use ExUnit.Case, async: true

  alias ArcaNotionex.AstToBlocks
  alias ArcaNotionex.LinkMap
  alias ArcaNotionex.Schemas.{NotionBlock, RichText}

  describe "convert/1" do
    test "converts heading 1" do
      markdown = "# Hello World"

      assert {:ok, [[block]]} = AstToBlocks.convert(markdown)
      assert block.type == :heading_1
      assert [%RichText{content: "Hello World"}] = block.rich_text
    end

    test "converts heading 2" do
      markdown = "## Section Title"

      assert {:ok, [[block]]} = AstToBlocks.convert(markdown)
      assert block.type == :heading_2
    end

    test "converts heading 3" do
      markdown = "### Subsection"

      assert {:ok, [[block]]} = AstToBlocks.convert(markdown)
      assert block.type == :heading_3
    end

    test "converts h4-h6 to heading_3" do
      markdown = """
      #### H4
      ##### H5
      ###### H6
      """

      assert {:ok, [blocks]} = AstToBlocks.convert(markdown)
      assert length(blocks) == 3
      assert Enum.all?(blocks, fn b -> b.type == :heading_3 end)
    end

    test "converts paragraph" do
      markdown = "This is a simple paragraph."

      assert {:ok, [[block]]} = AstToBlocks.convert(markdown)
      assert block.type == :paragraph
      assert [%RichText{content: "This is a simple paragraph."}] = block.rich_text
    end

    test "converts bold text" do
      markdown = "This is **bold** text."

      assert {:ok, [[block]]} = AstToBlocks.convert(markdown)
      assert block.type == :paragraph

      assert [
               %RichText{content: "This is ", bold: false},
               %RichText{content: "bold", bold: true},
               %RichText{content: " text.", bold: false}
             ] = block.rich_text
    end

    test "converts italic text" do
      markdown = "This is *italic* text."

      assert {:ok, [[block]]} = AstToBlocks.convert(markdown)

      assert Enum.any?(block.rich_text, fn rt ->
               rt.content == "italic" and rt.italic == true
             end)
    end

    test "converts inline code" do
      markdown = "Use `code` here."

      assert {:ok, [[block]]} = AstToBlocks.convert(markdown)

      assert Enum.any?(block.rich_text, fn rt ->
               rt.content == "code" and rt.code == true
             end)
    end

    test "converts links" do
      markdown = "Visit [Google](https://google.com) today."

      assert {:ok, [[block]]} = AstToBlocks.convert(markdown)

      assert Enum.any?(block.rich_text, fn rt ->
               rt.content == "Google" and rt.link == "https://google.com"
             end)
    end

    test "converts bulleted list" do
      markdown = """
      - Item 1
      - Item 2
      - Item 3
      """

      assert {:ok, [blocks]} = AstToBlocks.convert(markdown)
      assert length(blocks) == 3
      assert Enum.all?(blocks, fn b -> b.type == :bulleted_list_item end)
    end

    test "converts numbered list" do
      markdown = """
      1. First
      2. Second
      3. Third
      """

      assert {:ok, [blocks]} = AstToBlocks.convert(markdown)
      assert length(blocks) == 3
      assert Enum.all?(blocks, fn b -> b.type == :numbered_list_item end)
    end

    test "converts code block with language" do
      markdown = """
      ```elixir
      def hello, do: :world
      ```
      """

      assert {:ok, [[block]]} = AstToBlocks.convert(markdown)
      assert block.type == :code
      assert block.language == "elixir"
      assert [%RichText{content: content}] = block.rich_text
      assert content =~ "def hello"
    end

    test "converts code block without language" do
      markdown = """
      ```
      plain code
      ```
      """

      assert {:ok, [[block]]} = AstToBlocks.convert(markdown)
      assert block.type == :code
      assert block.language == "plain text"
    end

    test "converts blockquote" do
      markdown = "> This is a quote"

      assert {:ok, [[block]]} = AstToBlocks.convert(markdown)
      assert block.type == :quote
      assert [%RichText{content: "This is a quote"}] = block.rich_text
    end

    test "converts table" do
      markdown = """
      | Header 1 | Header 2 |
      |----------|----------|
      | Cell 1   | Cell 2   |
      | Cell 3   | Cell 4   |
      """

      assert {:ok, [[block]]} = AstToBlocks.convert(markdown)
      assert block.type == :table
      assert block.table_width == 2
      assert block.has_column_header == true
      assert length(block.children) == 3
    end

    test "handles nested formatting" do
      markdown = "This is ***bold and italic*** text."

      assert {:ok, [[block]]} = AstToBlocks.convert(markdown)

      assert Enum.any?(block.rich_text, fn rt ->
               rt.bold == true and rt.italic == true
             end)
    end

    test "handles empty markdown" do
      markdown = ""

      assert {:ok, []} = AstToBlocks.convert(markdown)
    end

    test "handles multiple paragraphs" do
      markdown = """
      First paragraph.

      Second paragraph.
      """

      assert {:ok, [blocks]} = AstToBlocks.convert(markdown)
      assert length(blocks) == 2
      assert Enum.all?(blocks, fn b -> b.type == :paragraph end)
    end
  end

  describe "to_notion/1" do
    test "converts paragraph block to Notion format" do
      block = NotionBlock.paragraph([RichText.text("Hello")])
      notion = NotionBlock.to_notion(block)

      assert notion["type"] == "paragraph"
      assert notion["paragraph"]["rich_text"] != []
    end

    test "converts heading block to Notion format" do
      block = NotionBlock.heading_1([RichText.text("Title")])
      notion = NotionBlock.to_notion(block)

      assert notion["type"] == "heading_1"
      assert notion["heading_1"]["rich_text"] != []
    end

    test "converts code block to Notion format" do
      block = NotionBlock.code([RichText.text("puts 'hello'")], "ruby")
      notion = NotionBlock.to_notion(block)

      assert notion["type"] == "code"
      assert notion["code"]["language"] == "ruby"
    end

    test "converts table to Notion format" do
      row1 = NotionBlock.table_row([[RichText.text("A")], [RichText.text("B")]])
      row2 = NotionBlock.table_row([[RichText.text("C")], [RichText.text("D")]])
      table = NotionBlock.table(2, [row1, row2], has_column_header: true)

      notion = NotionBlock.to_notion(table)

      assert notion["type"] == "table"
      assert notion["table"]["table_width"] == 2
      assert notion["table"]["has_column_header"] == true
      assert length(notion["table"]["children"]) == 2
    end
  end

  describe "children_to_rich_text/1" do
    test "converts plain text" do
      result = AstToBlocks.children_to_rich_text(["Hello World"])
      assert [%RichText{content: "Hello World"}] = result
    end

    test "converts nested strong" do
      ast = [{"strong", [], ["bold"], %{}}]
      result = AstToBlocks.children_to_rich_text(ast)
      assert [%RichText{content: "bold", bold: true}] = result
    end

    test "converts nested em" do
      ast = [{"em", [], ["italic"], %{}}]
      result = AstToBlocks.children_to_rich_text(ast)
      assert [%RichText{content: "italic", italic: true}] = result
    end
  end

  describe "convert/2 with link_map option" do
    @test_dir "test/fixtures/ast_link_test"

    setup do
      File.mkdir_p!(@test_dir)

      # Create test files with notion_ids
      File.write!(Path.join(@test_dir, "overview.md"), """
      ---
      title: Overview
      notion_id: abc123
      ---
      # Overview
      """)

      File.write!(Path.join(@test_dir, "guide.md"), """
      ---
      title: Guide
      notion_id: def456
      ---
      # Guide
      """)

      {:ok, link_map} = LinkMap.build(@test_dir)

      on_exit(fn ->
        File.rm_rf!(@test_dir)
      end)

      {:ok, link_map: link_map}
    end

    test "resolves internal .md links to page mentions", %{link_map: link_map} do
      markdown = "Read the [overview](overview.md) for details."

      {:ok, [[block]]} = AstToBlocks.convert(markdown, link_map: link_map)

      mention_rt = Enum.find(block.rich_text, fn rt -> rt.type == "mention" end)
      assert mention_rt.page_id == "abc123"
      assert mention_rt.content == "overview"
    end

    test "resolves links with anchors to page mentions (anchor ignored)", %{link_map: link_map} do
      # Note: page mentions don't support anchors, so the anchor is dropped
      markdown = "See [section](overview.md#intro)."

      {:ok, [[block]]} = AstToBlocks.convert(markdown, link_map: link_map)

      mention_rt = Enum.find(block.rich_text, fn rt -> rt.type == "mention" end)
      assert mention_rt.page_id == "abc123"
    end

    test "preserves external links", %{link_map: link_map} do
      markdown = "Visit [Google](https://google.com)."

      {:ok, [[block]]} = AstToBlocks.convert(markdown, link_map: link_map)

      link_rt = Enum.find(block.rich_text, fn rt -> rt.content == "Google" end)
      assert link_rt.link == "https://google.com"
    end

    test "preserves unresolvable internal links", %{link_map: link_map} do
      markdown = "See [other](unknown.md)."

      {:ok, [[block]]} = AstToBlocks.convert(markdown, link_map: link_map)

      link_rt = Enum.find(block.rich_text, fn rt -> rt.content == "other" end)
      assert link_rt.link == "unknown.md"
    end

    test "resolves links in headings to page mentions", %{link_map: link_map} do
      markdown = "# Check [guide](guide.md)"

      {:ok, [[block]]} = AstToBlocks.convert(markdown, link_map: link_map)

      assert block.type == :heading_1
      mention_rt = Enum.find(block.rich_text, fn rt -> rt.type == "mention" end)
      assert mention_rt.page_id == "def456"
    end

    test "resolves links in list items to page mentions", %{link_map: link_map} do
      markdown = """
      - See [overview](overview.md)
      - See [guide](guide.md)
      """

      {:ok, [blocks]} = AstToBlocks.convert(markdown, link_map: link_map)

      assert length(blocks) == 2

      [item1, item2] = blocks
      mention1 = Enum.find(item1.rich_text, fn rt -> rt.type == "mention" end)
      mention2 = Enum.find(item2.rich_text, fn rt -> rt.type == "mention" end)

      assert mention1.page_id == "abc123"
      assert mention2.page_id == "def456"
    end

    test "resolves links in blockquotes to page mentions", %{link_map: link_map} do
      markdown = "> Read [overview](overview.md)"

      {:ok, [[block]]} = AstToBlocks.convert(markdown, link_map: link_map)

      assert block.type == :quote
      mention_rt = Enum.find(block.rich_text, fn rt -> rt.type == "mention" end)
      assert mention_rt.page_id == "abc123"
    end

    test "handles current_file for relative path resolution", %{link_map: _link_map} do
      # Simulate being in a subdirectory
      File.mkdir_p!(Path.join(@test_dir, "docs"))

      File.write!(Path.join(@test_dir, "docs/child.md"), """
      ---
      title: Child
      notion_id: child-id
      ---
      # Child
      """)

      # Rebuild link map with the new file
      {:ok, link_map} = LinkMap.build(@test_dir)

      # Link from docs/child.md to ../overview.md
      markdown = "See [overview](../overview.md)"

      {:ok, [[block]]} =
        AstToBlocks.convert(markdown, link_map: link_map, current_file: "docs/child.md")

      mention_rt = Enum.find(block.rich_text, fn rt -> rt.type == "mention" end)
      assert mention_rt.page_id == "abc123"
    end

    test "converts without link_map (no resolution)" do
      markdown = "See [overview](overview.md)."

      {:ok, [[block]]} = AstToBlocks.convert(markdown)

      link_rt = Enum.find(block.rich_text, fn rt -> rt.content == "overview" end)
      assert link_rt.link == "overview.md"
    end
  end
end
