defmodule ArcaNotionex.BlocksToMarkdownTest do
  use ExUnit.Case, async: true

  alias ArcaNotionex.BlocksToMarkdown
  alias ArcaNotionex.Schemas.{NotionBlock, RichText}

  describe "convert/2" do
    test "converts heading_1 block" do
      blocks = [NotionBlock.heading_1([RichText.text("Main Title")])]

      assert {:ok, "# Main Title\n"} = BlocksToMarkdown.convert(blocks)
    end

    test "converts heading_2 block" do
      blocks = [NotionBlock.heading_2([RichText.text("Section")])]

      assert {:ok, "## Section\n"} = BlocksToMarkdown.convert(blocks)
    end

    test "converts heading_3 block" do
      blocks = [NotionBlock.heading_3([RichText.text("Subsection")])]

      assert {:ok, "### Subsection\n"} = BlocksToMarkdown.convert(blocks)
    end

    test "converts paragraph block" do
      blocks = [NotionBlock.paragraph([RichText.text("Hello world")])]

      assert {:ok, "Hello world\n"} = BlocksToMarkdown.convert(blocks)
    end

    test "converts bulleted_list_item block" do
      blocks = [NotionBlock.bulleted_list_item([RichText.text("Item one")])]

      assert {:ok, "- Item one\n"} = BlocksToMarkdown.convert(blocks)
    end

    test "converts numbered_list_item block" do
      blocks = [NotionBlock.numbered_list_item([RichText.text("Step one")])]

      assert {:ok, "1. Step one\n"} = BlocksToMarkdown.convert(blocks)
    end

    test "converts code block with language" do
      blocks = [NotionBlock.code([RichText.text("def hello, do: :world")], "elixir")]

      assert {:ok, markdown} = BlocksToMarkdown.convert(blocks)
      assert markdown == "```elixir\ndef hello, do: :world\n```\n"
    end

    test "converts code block without language" do
      blocks = [NotionBlock.code([RichText.text("some code")])]

      assert {:ok, markdown} = BlocksToMarkdown.convert(blocks)
      assert markdown =~ "```plain text"
    end

    test "converts quote block" do
      blocks = [NotionBlock.quote([RichText.text("Famous quote")])]

      assert {:ok, "> Famous quote\n"} = BlocksToMarkdown.convert(blocks)
    end

    test "handles empty block list" do
      assert {:ok, ""} = BlocksToMarkdown.convert([])
    end

    test "handles multiple blocks with blank lines" do
      blocks = [
        NotionBlock.heading_1([RichText.text("Title")]),
        NotionBlock.paragraph([RichText.text("Text")])
      ]

      assert {:ok, markdown} = BlocksToMarkdown.convert(blocks)
      assert markdown == "# Title\n\nText\n"
    end
  end

  describe "rich text rendering" do
    test "renders plain text" do
      blocks = [NotionBlock.paragraph([RichText.text("Plain text")])]

      assert {:ok, "Plain text\n"} = BlocksToMarkdown.convert(blocks)
    end

    test "renders bold text" do
      blocks = [NotionBlock.paragraph([RichText.bold("Bold text")])]

      assert {:ok, "**Bold text**\n"} = BlocksToMarkdown.convert(blocks)
    end

    test "renders italic text" do
      blocks = [NotionBlock.paragraph([RichText.italic("Italic text")])]

      assert {:ok, "*Italic text*\n"} = BlocksToMarkdown.convert(blocks)
    end

    test "renders inline code" do
      blocks = [NotionBlock.paragraph([RichText.code("inline_code")])]

      assert {:ok, "`inline_code`\n"} = BlocksToMarkdown.convert(blocks)
    end

    test "renders strikethrough text" do
      rt = %RichText{content: "deleted", strikethrough: true}
      blocks = [NotionBlock.paragraph([rt])]

      assert {:ok, "~~deleted~~\n"} = BlocksToMarkdown.convert(blocks)
    end

    test "renders links" do
      blocks = [NotionBlock.paragraph([RichText.link("Click here", "https://example.com")])]

      assert {:ok, "[Click here](https://example.com)\n"} = BlocksToMarkdown.convert(blocks)
    end

    test "renders combined bold and italic" do
      rt = %RichText{content: "Important", bold: true, italic: true}
      blocks = [NotionBlock.paragraph([rt])]

      assert {:ok, markdown} = BlocksToMarkdown.convert(blocks)
      # Order: code, bold, italic, strikethrough, link
      assert markdown == "***Important***\n"
    end

    test "preserves underline in HTML comment" do
      rt = %RichText{content: "underlined", underline: true}
      blocks = [NotionBlock.paragraph([rt])]

      assert {:ok, markdown} = BlocksToMarkdown.convert(blocks, preserve_metadata: true)
      assert markdown =~ "<!-- notion:underline -->underlined<!-- /notion:underline -->"
    end

    test "preserves color in HTML comment" do
      rt = %RichText{content: "colored", color: "red"}
      blocks = [NotionBlock.paragraph([rt])]

      assert {:ok, markdown} = BlocksToMarkdown.convert(blocks, preserve_metadata: true)
      assert markdown =~ "<!-- notion:color=red -->colored<!-- /notion:color -->"
    end

    test "omits HTML comments when preserve_metadata is false" do
      rt = %RichText{content: "underlined", underline: true, color: "blue"}
      blocks = [NotionBlock.paragraph([rt])]

      assert {:ok, markdown} = BlocksToMarkdown.convert(blocks, preserve_metadata: false)
      refute markdown =~ "<!-- notion:"
      assert markdown == "underlined\n"
    end
  end

  describe "table conversion" do
    test "converts simple table with header" do
      header = NotionBlock.table_row([
        [RichText.text("A")],
        [RichText.text("B")]
      ])

      row1 = NotionBlock.table_row([
        [RichText.text("1")],
        [RichText.text("2")]
      ])

      table = NotionBlock.table(2, [header, row1], has_column_header: true)

      assert {:ok, markdown} = BlocksToMarkdown.convert([table])
      assert markdown =~ "| A | B |"
      assert markdown =~ "| --- | --- |"
      assert markdown =~ "| 1 | 2 |"
    end

    test "escapes pipes in cell content" do
      row = NotionBlock.table_row([
        [RichText.text("A | B")],
        [RichText.text("C")]
      ])

      table = NotionBlock.table(2, [row])

      assert {:ok, markdown} = BlocksToMarkdown.convert([table])
      assert markdown =~ "A \\| B"
    end
  end

  describe "nested lists" do
    test "handles one level of nesting" do
      child = NotionBlock.bulleted_list_item([RichText.text("Child item")])
      parent = NotionBlock.bulleted_list_item([RichText.text("Parent item")], [child])

      assert {:ok, markdown} = BlocksToMarkdown.convert([parent])
      assert markdown =~ "- Parent item"
      assert markdown =~ "  - Child item"
    end

    test "handles multiple levels of nesting" do
      grandchild = NotionBlock.bulleted_list_item([RichText.text("Grandchild")])
      child = NotionBlock.bulleted_list_item([RichText.text("Child")], [grandchild])
      parent = NotionBlock.bulleted_list_item([RichText.text("Parent")], [child])

      assert {:ok, markdown} = BlocksToMarkdown.convert([parent])
      assert markdown =~ "- Parent"
      assert markdown =~ "  - Child"
      assert markdown =~ "    - Grandchild"
    end
  end

  describe "options" do
    test "preserve_metadata: false omits HTML comments" do
      rt = %RichText{content: "test", underline: true}
      blocks = [NotionBlock.paragraph([rt])]

      assert {:ok, markdown} = BlocksToMarkdown.convert(blocks, preserve_metadata: false)
      refute markdown =~ "<!--"
    end

    test "preserve_metadata: true (default) includes HTML comments" do
      rt = %RichText{content: "test", underline: true}
      blocks = [NotionBlock.paragraph([rt])]

      assert {:ok, markdown} = BlocksToMarkdown.convert(blocks)
      assert markdown =~ "<!-- notion:underline -->"
    end
  end

  describe "round-trip integration" do
    test "paragraph round-trip: blocks -> markdown -> readable" do
      blocks = [NotionBlock.paragraph([RichText.text("Hello world")])]

      assert {:ok, "Hello world\n"} = BlocksToMarkdown.convert(blocks)
    end

    test "formatted text round-trip" do
      blocks = [
        NotionBlock.paragraph([
          RichText.text("Normal "),
          RichText.bold("bold"),
          RichText.text(" and "),
          RichText.italic("italic")
        ])
      ]

      assert {:ok, markdown} = BlocksToMarkdown.convert(blocks)
      assert markdown == "Normal **bold** and *italic*\n"
    end
  end
end
