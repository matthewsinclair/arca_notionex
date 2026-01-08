defmodule ArcaNotionex.BlocksToMarkdown do
  @moduledoc """
  Converts Notion blocks to Markdown text.

  This is the inverse of `AstToBlocks` - it takes NotionBlock structs and produces
  valid Markdown that can round-trip back to Notion.

  ## Fidelity Preservation

  Notion-specific data that cannot be represented in standard Markdown
  is preserved in HTML comments for round-tripping:

  - Underline: `<!-- notion:underline -->text<!-- /notion:underline -->`
  - Text color: `<!-- notion:color=red -->text<!-- /notion:color -->`

  ## Link Resolution

  When a LinkMap is provided, Notion URLs are resolved back to local markdown paths:

  - `https://notion.so/abc123` → `[text](relative/path.md)`

  ## Example

      blocks = [NotionBlock.heading_1([RichText.text("Title")])]
      {:ok, markdown} = BlocksToMarkdown.convert(blocks)
      # "# Title\\n"

  """

  alias ArcaNotionex.Schemas.{NotionBlock, RichText}
  alias ArcaNotionex.LinkMap

  @type convert_opts :: [
          preserve_metadata: boolean(),
          indent_level: non_neg_integer(),
          link_map: LinkMap.t() | nil
        ]
  @type convert_result :: {:ok, String.t()} | {:error, atom(), String.t()}

  @doc """
  Converts a list of NotionBlock structs to Markdown.

  ## Options

  - `:preserve_metadata` - If true, embeds Notion-specific data in HTML comments (default: true)
  - `:indent_level` - Starting indent level for nested lists (default: 0)
  - `:link_map` - LinkMap for resolving Notion URLs to local paths (default: nil)

  ## Examples

      iex> blocks = [NotionBlock.heading_1([RichText.text("Hello")])]
      iex> {:ok, markdown} = BlocksToMarkdown.convert(blocks)
      iex> markdown
      "# Hello\\n"

  """
  @spec convert([NotionBlock.t()], convert_opts()) :: convert_result()
  def convert(blocks, opts \\ []) when is_list(blocks) do
    result =
      blocks
      |> Enum.map(&convert_block(&1, opts))
      |> Enum.reject(&(&1 == ""))
      |> join_with_blank_lines()

    {:ok, result}
  rescue
    e -> {:error, :conversion_error, Exception.message(e)}
  end

  @doc """
  Renders a list of RichText structs to Markdown inline text.
  """
  @spec render_rich_text([RichText.t()], convert_opts()) :: String.t()
  def render_rich_text(rich_texts, opts \\ []) when is_list(rich_texts) do
    rich_texts
    |> Enum.map(&render_rich_text_item(&1, opts))
    |> Enum.join("")
  end

  # Block type dispatch

  defp convert_block(%NotionBlock{type: :heading_1} = block, opts) do
    text = render_rich_text(block.rich_text, opts)
    "# #{text}"
  end

  defp convert_block(%NotionBlock{type: :heading_2} = block, opts) do
    text = render_rich_text(block.rich_text, opts)
    "## #{text}"
  end

  defp convert_block(%NotionBlock{type: :heading_3} = block, opts) do
    text = render_rich_text(block.rich_text, opts)
    "### #{text}"
  end

  defp convert_block(%NotionBlock{type: :paragraph} = block, opts) do
    render_rich_text(block.rich_text, opts)
  end

  defp convert_block(%NotionBlock{type: :bulleted_list_item} = block, opts) do
    convert_list_item(block, "-", opts)
  end

  defp convert_block(%NotionBlock{type: :numbered_list_item} = block, opts) do
    convert_list_item(block, "1.", opts)
  end

  defp convert_block(%NotionBlock{type: :code} = block, _opts) do
    code = extract_code_content(block.rich_text)
    language = block.language || "plain text"
    "```#{language}\n#{code}\n```"
  end

  defp convert_block(%NotionBlock{type: :quote} = block, opts) do
    text = render_rich_text(block.rich_text, opts)

    lines =
      text
      |> String.split("\n")
      |> Enum.map(&"> #{&1}")
      |> Enum.join("\n")

    lines
  end

  defp convert_block(%NotionBlock{type: :table} = block, opts) do
    convert_table(block, opts)
  end

  defp convert_block(%NotionBlock{type: :table_row}, _opts) do
    # Table rows are handled by convert_table
    ""
  end

  defp convert_block(_unknown, _opts) do
    # Skip unsupported block types
    ""
  end

  # List item conversion with nesting

  defp convert_list_item(%NotionBlock{} = block, marker, opts) do
    indent_level = Keyword.get(opts, :indent_level, 0)
    indent = String.duplicate("  ", indent_level)

    text = render_rich_text(block.rich_text, opts)
    main_line = "#{indent}#{marker} #{text}"

    children_md =
      if block.children != [] do
        child_opts = Keyword.put(opts, :indent_level, indent_level + 1)

        block.children
        |> Enum.map(&convert_block(&1, child_opts))
        |> Enum.reject(&(&1 == ""))
        |> Enum.join("\n")
      else
        ""
      end

    if children_md != "" do
      main_line <> "\n" <> children_md
    else
      main_line
    end
  end

  # Rich text rendering

  defp render_rich_text_item(%RichText{} = rt, opts) do
    content = rt.content || ""
    preserve = Keyword.get(opts, :preserve_metadata, true)
    link_map = Keyword.get(opts, :link_map)

    content
    |> maybe_wrap_code(rt)
    |> maybe_wrap_bold(rt)
    |> maybe_wrap_italic(rt)
    |> maybe_wrap_strikethrough(rt)
    |> maybe_wrap_link(rt, link_map)
    |> maybe_wrap_underline(rt, preserve)
    |> maybe_wrap_color(rt, preserve)
  end

  defp maybe_wrap_code(text, %RichText{code: true}), do: "`#{text}`"
  defp maybe_wrap_code(text, _), do: text

  defp maybe_wrap_bold(text, %RichText{bold: true}), do: "**#{text}**"
  defp maybe_wrap_bold(text, _), do: text

  defp maybe_wrap_italic(text, %RichText{italic: true}), do: "*#{text}*"
  defp maybe_wrap_italic(text, _), do: text

  defp maybe_wrap_strikethrough(text, %RichText{strikethrough: true}), do: "~~#{text}~~"
  defp maybe_wrap_strikethrough(text, _), do: text

  defp maybe_wrap_link(text, %RichText{link: link}, link_map) when is_binary(link) and link != "" do
    resolved_link = resolve_link(link, link_map)
    "[#{text}](#{resolved_link})"
  end

  defp maybe_wrap_link(text, %RichText{href: href}, link_map)
       when is_binary(href) and href != "" do
    resolved_link = resolve_link(href, link_map)
    "[#{text}](#{resolved_link})"
  end

  defp maybe_wrap_link(text, _, _), do: text

  defp resolve_link(link, nil), do: link

  defp resolve_link(link, link_map) do
    LinkMap.resolve_link(link_map, link, direction: :reverse)
  end

  # Notion-specific: underline (no MD equivalent)
  defp maybe_wrap_underline(text, %RichText{underline: true}, true = _preserve) do
    "<!-- notion:underline -->#{text}<!-- /notion:underline -->"
  end

  defp maybe_wrap_underline(text, _, _), do: text

  # Notion-specific: color (no MD equivalent)
  defp maybe_wrap_color(text, %RichText{color: color}, true = _preserve)
       when color != "default" and not is_nil(color) do
    "<!-- notion:color=#{color} -->#{text}<!-- /notion:color -->"
  end

  defp maybe_wrap_color(text, _, _), do: text

  # Table conversion

  defp convert_table(%NotionBlock{type: :table} = block, opts) do
    rows = block.children
    width = block.table_width || 0
    has_header = block.has_column_header

    case rows do
      [] ->
        ""

      [first_row | rest_rows] ->
        if has_header do
          header_row = render_table_row(first_row, opts)
          separator = generate_separator(width)
          body_rows = Enum.map(rest_rows, &render_table_row(&1, opts))

          ([header_row, separator] ++ body_rows)
          |> Enum.join("\n")
        else
          # No header - all rows are body
          all_rows = Enum.map(rows, &render_table_row(&1, opts))
          Enum.join(all_rows, "\n")
        end
    end
  end

  defp render_table_row(%NotionBlock{type: :table_row, cells: cells}, opts) do
    cell_contents =
      cells
      |> Enum.map(fn cell_rich_text ->
        render_rich_text(cell_rich_text, opts)
        |> String.replace("|", "\\|")
        |> String.trim()
      end)

    "| #{Enum.join(cell_contents, " | ")} |"
  end

  defp generate_separator(width) when width > 0 do
    cells = Enum.map(1..width, fn _ -> "---" end)
    "| #{Enum.join(cells, " | ")} |"
  end

  defp generate_separator(_), do: "| --- |"

  # Helper functions

  defp extract_code_content(rich_texts) do
    rich_texts
    |> Enum.map(&(&1.content || ""))
    |> Enum.join("")
  end

  defp join_with_blank_lines([]), do: ""

  defp join_with_blank_lines(strings) do
    strings
    |> Enum.join("\n\n")
    |> String.trim()
    |> Kernel.<>("\n")
  end
end
