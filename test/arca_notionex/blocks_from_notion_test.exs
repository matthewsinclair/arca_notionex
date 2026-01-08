defmodule ArcaNotionex.BlocksFromNotionTest do
  use ExUnit.Case, async: true

  alias ArcaNotionex.BlocksFromNotion
  alias ArcaNotionex.Schemas.{NotionBlock, RichText}

  describe "parse/1" do
    test "parses paragraph block" do
      blocks = [
        %{
          "type" => "paragraph",
          "paragraph" => %{
            "rich_text" => [
              %{
                "type" => "text",
                "text" => %{"content" => "Hello world"},
                "annotations" => %{
                  "bold" => false,
                  "italic" => false,
                  "code" => false,
                  "strikethrough" => false,
                  "underline" => false,
                  "color" => "default"
                },
                "plain_text" => "Hello world",
                "href" => nil
              }
            ],
            "color" => "default"
          }
        }
      ]

      assert {:ok, [block]} = BlocksFromNotion.parse(blocks)
      assert block.type == :paragraph
      assert [%RichText{content: "Hello world"}] = block.rich_text
    end

    test "parses heading_1 block" do
      blocks = [
        %{
          "type" => "heading_1",
          "heading_1" => %{
            "rich_text" => [
              %{
                "type" => "text",
                "text" => %{"content" => "Main Title"},
                "annotations" => %{},
                "plain_text" => "Main Title"
              }
            ],
            "color" => "default",
            "is_toggleable" => false
          }
        }
      ]

      assert {:ok, [block]} = BlocksFromNotion.parse(blocks)
      assert block.type == :heading_1
      assert [%RichText{content: "Main Title"}] = block.rich_text
      assert block.is_toggleable == false
    end

    test "parses heading_2 block" do
      blocks = [
        %{
          "type" => "heading_2",
          "heading_2" => %{
            "rich_text" => [%{"type" => "text", "text" => %{"content" => "Section"}}],
            "color" => "blue"
          }
        }
      ]

      assert {:ok, [block]} = BlocksFromNotion.parse(blocks)
      assert block.type == :heading_2
      assert block.color == "blue"
    end

    test "parses heading_3 block" do
      blocks = [
        %{
          "type" => "heading_3",
          "heading_3" => %{
            "rich_text" => [%{"type" => "text", "text" => %{"content" => "Subsection"}}]
          }
        }
      ]

      assert {:ok, [block]} = BlocksFromNotion.parse(blocks)
      assert block.type == :heading_3
    end

    test "parses bulleted_list_item block" do
      blocks = [
        %{
          "type" => "bulleted_list_item",
          "bulleted_list_item" => %{
            "rich_text" => [%{"type" => "text", "text" => %{"content" => "Item one"}}],
            "color" => "default"
          }
        }
      ]

      assert {:ok, [block]} = BlocksFromNotion.parse(blocks)
      assert block.type == :bulleted_list_item
      assert [%RichText{content: "Item one"}] = block.rich_text
    end

    test "parses numbered_list_item block" do
      blocks = [
        %{
          "type" => "numbered_list_item",
          "numbered_list_item" => %{
            "rich_text" => [%{"type" => "text", "text" => %{"content" => "Step 1"}}],
            "color" => "default"
          }
        }
      ]

      assert {:ok, [block]} = BlocksFromNotion.parse(blocks)
      assert block.type == :numbered_list_item
      assert [%RichText{content: "Step 1"}] = block.rich_text
    end

    test "parses code block with language" do
      blocks = [
        %{
          "type" => "code",
          "code" => %{
            "rich_text" => [
              %{
                "type" => "text",
                "text" => %{"content" => "def hello, do: :world"},
                "annotations" => %{},
                "plain_text" => "def hello, do: :world"
              }
            ],
            "language" => "elixir"
          }
        }
      ]

      assert {:ok, [block]} = BlocksFromNotion.parse(blocks)
      assert block.type == :code
      assert block.language == "elixir"
      assert [%RichText{content: "def hello, do: :world"}] = block.rich_text
    end

    test "parses quote block" do
      blocks = [
        %{
          "type" => "quote",
          "quote" => %{
            "rich_text" => [%{"type" => "text", "text" => %{"content" => "Famous quote"}}],
            "color" => "default"
          }
        }
      ]

      assert {:ok, [block]} = BlocksFromNotion.parse(blocks)
      assert block.type == :quote
      assert [%RichText{content: "Famous quote"}] = block.rich_text
    end

    test "parses table block" do
      blocks = [
        %{
          "type" => "table",
          "table" => %{
            "table_width" => 3,
            "has_column_header" => true,
            "has_row_header" => false
          }
        }
      ]

      assert {:ok, [block]} = BlocksFromNotion.parse(blocks)
      assert block.type == :table
      assert block.table_width == 3
      assert block.has_column_header == true
      assert block.has_row_header == false
    end

    test "parses table_row block" do
      blocks = [
        %{
          "type" => "table_row",
          "table_row" => %{
            "cells" => [
              [%{"type" => "text", "text" => %{"content" => "A"}}],
              [%{"type" => "text", "text" => %{"content" => "B"}}],
              [%{"type" => "text", "text" => %{"content" => "C"}}]
            ]
          }
        }
      ]

      assert {:ok, [block]} = BlocksFromNotion.parse(blocks)
      assert block.type == :table_row
      assert length(block.cells) == 3

      assert [[%RichText{content: "A"}], [%RichText{content: "B"}], [%RichText{content: "C"}]] =
               block.cells
    end

    test "skips unsupported block types" do
      blocks = [
        %{"type" => "divider", "divider" => %{}},
        %{"type" => "paragraph", "paragraph" => %{"rich_text" => []}}
      ]

      assert {:ok, [block]} = BlocksFromNotion.parse(blocks)
      assert block.type == :paragraph
    end

    test "handles multiple blocks" do
      blocks = [
        %{
          "type" => "heading_1",
          "heading_1" => %{
            "rich_text" => [%{"type" => "text", "text" => %{"content" => "Title"}}]
          }
        },
        %{
          "type" => "paragraph",
          "paragraph" => %{"rich_text" => [%{"type" => "text", "text" => %{"content" => "Text"}}]}
        }
      ]

      assert {:ok, parsed} = BlocksFromNotion.parse(blocks)
      assert length(parsed) == 2
      assert [%NotionBlock{type: :heading_1}, %NotionBlock{type: :paragraph}] = parsed
    end

    test "handles empty block list" do
      assert {:ok, []} = BlocksFromNotion.parse([])
    end
  end

  describe "rich text parsing" do
    test "parses bold text" do
      blocks = [
        %{
          "type" => "paragraph",
          "paragraph" => %{
            "rich_text" => [
              %{
                "type" => "text",
                "text" => %{"content" => "Bold text"},
                "annotations" => %{"bold" => true},
                "plain_text" => "Bold text"
              }
            ]
          }
        }
      ]

      assert {:ok, [block]} = BlocksFromNotion.parse(blocks)
      assert [%RichText{content: "Bold text", bold: true}] = block.rich_text
    end

    test "parses italic text" do
      blocks = [
        %{
          "type" => "paragraph",
          "paragraph" => %{
            "rich_text" => [
              %{
                "type" => "text",
                "text" => %{"content" => "Italic text"},
                "annotations" => %{"italic" => true}
              }
            ]
          }
        }
      ]

      assert {:ok, [block]} = BlocksFromNotion.parse(blocks)
      assert [%RichText{italic: true}] = block.rich_text
    end

    test "parses inline code" do
      blocks = [
        %{
          "type" => "paragraph",
          "paragraph" => %{
            "rich_text" => [
              %{
                "type" => "text",
                "text" => %{"content" => "code"},
                "annotations" => %{"code" => true}
              }
            ]
          }
        }
      ]

      assert {:ok, [block]} = BlocksFromNotion.parse(blocks)
      assert [%RichText{code: true}] = block.rich_text
    end

    test "parses strikethrough text" do
      blocks = [
        %{
          "type" => "paragraph",
          "paragraph" => %{
            "rich_text" => [
              %{
                "type" => "text",
                "text" => %{"content" => "deleted"},
                "annotations" => %{"strikethrough" => true}
              }
            ]
          }
        }
      ]

      assert {:ok, [block]} = BlocksFromNotion.parse(blocks)
      assert [%RichText{strikethrough: true}] = block.rich_text
    end

    test "parses underline text" do
      blocks = [
        %{
          "type" => "paragraph",
          "paragraph" => %{
            "rich_text" => [
              %{
                "type" => "text",
                "text" => %{"content" => "underlined"},
                "annotations" => %{"underline" => true}
              }
            ]
          }
        }
      ]

      assert {:ok, [block]} = BlocksFromNotion.parse(blocks)
      assert [%RichText{underline: true}] = block.rich_text
    end

    test "parses links" do
      blocks = [
        %{
          "type" => "paragraph",
          "paragraph" => %{
            "rich_text" => [
              %{
                "type" => "text",
                "text" => %{
                  "content" => "Click here",
                  "link" => %{"url" => "https://example.com"}
                },
                "href" => "https://example.com"
              }
            ]
          }
        }
      ]

      assert {:ok, [block]} = BlocksFromNotion.parse(blocks)
      assert [%RichText{content: "Click here", link: "https://example.com"}] = block.rich_text
    end

    test "parses combined annotations" do
      blocks = [
        %{
          "type" => "paragraph",
          "paragraph" => %{
            "rich_text" => [
              %{
                "type" => "text",
                "text" => %{"content" => "Important"},
                "annotations" => %{
                  "bold" => true,
                  "italic" => true,
                  "color" => "red"
                }
              }
            ]
          }
        }
      ]

      assert {:ok, [block]} = BlocksFromNotion.parse(blocks)
      assert [%RichText{bold: true, italic: true, color: "red"}] = block.rich_text
    end
  end

  describe "nested children" do
    test "parses inline children in list item" do
      blocks = [
        %{
          "type" => "bulleted_list_item",
          "bulleted_list_item" => %{
            "rich_text" => [%{"type" => "text", "text" => %{"content" => "Parent"}}],
            "children" => [
              %{
                "type" => "bulleted_list_item",
                "bulleted_list_item" => %{
                  "rich_text" => [%{"type" => "text", "text" => %{"content" => "Child"}}]
                }
              }
            ]
          }
        }
      ]

      assert {:ok, [block]} = BlocksFromNotion.parse(blocks)
      assert block.type == :bulleted_list_item
      assert [%RichText{content: "Parent"}] = block.rich_text
      assert [child] = block.children
      assert child.type == :bulleted_list_item
      assert [%RichText{content: "Child"}] = child.rich_text
    end

    test "parses table with rows as children" do
      blocks = [
        %{
          "type" => "table",
          "table" => %{
            "table_width" => 2,
            "has_column_header" => true,
            "children" => [
              %{
                "type" => "table_row",
                "table_row" => %{
                  "cells" => [
                    [%{"type" => "text", "text" => %{"content" => "Header 1"}}],
                    [%{"type" => "text", "text" => %{"content" => "Header 2"}}]
                  ]
                }
              },
              %{
                "type" => "table_row",
                "table_row" => %{
                  "cells" => [
                    [%{"type" => "text", "text" => %{"content" => "Data 1"}}],
                    [%{"type" => "text", "text" => %{"content" => "Data 2"}}]
                  ]
                }
              }
            ]
          }
        }
      ]

      assert {:ok, [table]} = BlocksFromNotion.parse(blocks)
      assert table.type == :table
      assert length(table.children) == 2
      assert [header_row, data_row] = table.children
      assert header_row.type == :table_row
      assert data_row.type == :table_row
    end
  end

  describe "round-trip with to_notion" do
    test "paragraph survives round-trip" do
      original = NotionBlock.paragraph([RichText.text("Test content")])
      json = NotionBlock.to_notion(original)

      assert {:ok, [parsed]} = BlocksFromNotion.parse([json])
      assert parsed.type == original.type
      assert hd(parsed.rich_text).content == hd(original.rich_text).content
    end

    test "heading survives round-trip" do
      original = NotionBlock.heading_1([RichText.bold("Title")])
      json = NotionBlock.to_notion(original)

      assert {:ok, [parsed]} = BlocksFromNotion.parse([json])
      assert parsed.type == :heading_1
      assert hd(parsed.rich_text).content == "Title"
      assert hd(parsed.rich_text).bold == true
    end

    test "code block survives round-trip" do
      original = NotionBlock.code([RichText.text("puts 'hello'")], "ruby")
      json = NotionBlock.to_notion(original)

      assert {:ok, [parsed]} = BlocksFromNotion.parse([json])
      assert parsed.type == :code
      assert parsed.language == "ruby"
      assert hd(parsed.rich_text).content == "puts 'hello'"
    end
  end
end
