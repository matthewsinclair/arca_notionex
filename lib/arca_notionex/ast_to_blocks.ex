defmodule ArcaNotionex.AstToBlocks do
  @moduledoc """
  Converts Earmark AST to Notion block format.

  EarmarkParser AST format: `{tag, attributes, children, metadata}` or plain string.
  Notion block format: `%NotionBlock{}` structs.

  ## Supported Conversions

  | Earmark | Notion Block |
  |---------|-------------|
  | h1-h3 | heading_1, heading_2, heading_3 |
  | h4-h6 | heading_3 (Notion max) |
  | p | paragraph |
  | ul > li | bulleted_list_item |
  | ol > li | numbered_list_item |
  | pre > code | code |
  | blockquote | quote |
  | table | table |
  | strong | rich_text: bold |
  | em | rich_text: italic |
  | code (inline) | rich_text: code |
  | a | rich_text with link |
  """

  alias ArcaNotionex.Schemas.{NotionBlock, RichText}
  alias ArcaNotionex.LinkMap

  @max_text_length 2000
  @max_blocks_per_chunk 100

  @type earmark_ast :: {String.t(), list(), list(), map()} | String.t()
  @type convert_result :: {:ok, [[NotionBlock.t()]]} | {:error, atom(), String.t()}
  @type convert_opts :: [link_map: LinkMap.t(), current_file: String.t()]

  @doc """
  Converts markdown content to Notion blocks.

  Returns `{:ok, chunks}` where chunks is a list of block lists (for API chunking).

  ## Options

  - `:link_map` - LinkMap for resolving internal .md links to Notion URLs
  - `:current_file` - Current file path for resolving relative links

  ## Examples

      # Without link resolution
      {:ok, blocks} = AstToBlocks.convert(markdown)

      # With link resolution (for --relink)
      {:ok, link_map} = LinkMap.build(dir)
      {:ok, blocks} = AstToBlocks.convert(markdown, link_map: link_map)

  """
  @spec convert(String.t(), convert_opts()) :: convert_result()
  def convert(markdown, opts \\ []) when is_binary(markdown) do
    case EarmarkParser.as_ast(markdown) do
      {:ok, ast, _deprecation_messages} ->
        blocks =
          ast
          |> Enum.flat_map(&convert_node(&1, opts))
          |> chunk_blocks()

        {:ok, blocks}

      {:error, _ast, errors} ->
        {:error, :parse_error, "Markdown parse error: #{inspect(errors)}"}
    end
  end

  @doc """
  Converts a single AST node to Notion block(s).
  """
  @spec convert_node(earmark_ast(), convert_opts()) :: [NotionBlock.t()]
  def convert_node(node, opts \\ [])

  def convert_node({"h1", _attrs, children, _meta}, opts) do
    [NotionBlock.heading_1(children_to_rich_text(children, opts))]
  end

  def convert_node({"h2", _attrs, children, _meta}, opts) do
    [NotionBlock.heading_2(children_to_rich_text(children, opts))]
  end

  def convert_node({"h3", _attrs, children, _meta}, opts) do
    [NotionBlock.heading_3(children_to_rich_text(children, opts))]
  end

  # h4, h5, h6 map to heading_3 (Notion max)
  def convert_node({"h4", _attrs, children, _meta}, opts) do
    [NotionBlock.heading_3(children_to_rich_text(children, opts))]
  end

  def convert_node({"h5", _attrs, children, _meta}, opts) do
    [NotionBlock.heading_3(children_to_rich_text(children, opts))]
  end

  def convert_node({"h6", _attrs, children, _meta}, opts) do
    [NotionBlock.heading_3(children_to_rich_text(children, opts))]
  end

  def convert_node({"p", _attrs, children, _meta}, opts) do
    # Check if paragraph contains only an image (images are block-level in Notion)
    case extract_standalone_image(children) do
      {:ok, image_node} ->
        convert_node(image_node, opts)

      :not_image ->
        rich_text = children_to_rich_text(children, opts)
        split_paragraph_blocks(rich_text)
    end
  end

  def convert_node({"ul", _attrs, children, _meta}, opts) do
    Enum.flat_map(children, fn
      {"li", _, li_children, _} ->
        {inline, nested} = separate_inline_and_nested(li_children)
        nested_blocks = Enum.flat_map(nested, &convert_node(&1, opts))
        [NotionBlock.bulleted_list_item(children_to_rich_text(inline, opts), nested_blocks)]

      _ ->
        []
    end)
  end

  def convert_node({"ol", _attrs, children, _meta}, opts) do
    Enum.flat_map(children, fn
      {"li", _, li_children, _} ->
        {inline, nested} = separate_inline_and_nested(li_children)
        nested_blocks = Enum.flat_map(nested, &convert_node(&1, opts))
        [NotionBlock.numbered_list_item(children_to_rich_text(inline, opts), nested_blocks)]

      _ ->
        []
    end)
  end

  def convert_node({"pre", _attrs, [{"code", code_attrs, [code_text], _}], _meta}, _opts)
      when is_binary(code_text) do
    language = extract_language(code_attrs)
    [NotionBlock.code([RichText.text(code_text)], language)]
  end

  def convert_node({"pre", _attrs, [{"code", code_attrs, code_children, _}], _meta}, _opts) do
    language = extract_language(code_attrs)
    code_text = flatten_text(code_children)
    [NotionBlock.code([RichText.text(code_text)], language)]
  end

  def convert_node({"blockquote", _attrs, children, _meta}, opts) do
    rich_text =
      Enum.flat_map(children, fn
        {"p", _, p_children, _} -> children_to_rich_text(p_children, opts)
        other -> children_to_rich_text([other], opts)
      end)

    [NotionBlock.quote(rich_text)]
  end

  def convert_node({"table", _attrs, children, _meta}, opts) do
    convert_table(children, opts)
  end

  def convert_node({"hr", _attrs, _children, _meta}, _opts) do
    # Horizontal rules become divider blocks (not yet supported, skip)
    []
  end

  def convert_node(text, _opts) when is_binary(text) do
    trimmed = String.trim(text)

    if trimmed == "" do
      []
    else
      [NotionBlock.paragraph([RichText.text(trimmed)])]
    end
  end

  def convert_node({"img", attrs, _, _}, _opts) do
    src = get_attr(attrs, "src")
    alt = get_attr(attrs, "alt") || ""

    cond do
      is_nil(src) or src == "" ->
        # Missing src - skip silently
        []

      String.starts_with?(src, "data:") ->
        # Data URLs not supported by Notion - skip silently
        []

      String.starts_with?(src, ["http://", "https://"]) ->
        # External URL - create image block
        [NotionBlock.image(src, alt)]

      true ->
        # Local/relative path - skip silently (Notion requires external URLs)
        []
    end
  end

  def convert_node(_unknown, _opts) do
    # Skip unsupported nodes
    []
  end

  # Rich text conversion

  @doc """
  Converts AST children to a list of RichText structs.
  """
  @spec children_to_rich_text(list(), convert_opts()) :: [RichText.t()]
  def children_to_rich_text(children, opts \\ []) do
    children
    |> Enum.flat_map(&node_to_rich_text(&1, opts))
    |> merge_adjacent_text()
  end

  defp node_to_rich_text(text, _opts) when is_binary(text) do
    [RichText.text(text)]
  end

  defp node_to_rich_text({"strong", _, children, _}, opts) do
    children
    |> children_to_rich_text(opts)
    |> Enum.map(&add_annotation(&1, :bold))
  end

  defp node_to_rich_text({"em", _, children, _}, opts) do
    children
    |> children_to_rich_text(opts)
    |> Enum.map(&add_annotation(&1, :italic))
  end

  defp node_to_rich_text({"code", _, [text], _}, _opts) when is_binary(text) do
    [RichText.code(text)]
  end

  defp node_to_rich_text({"a", attrs, children, _}, opts) do
    href = get_attr(attrs, "href")
    link_map = Keyword.get(opts, :link_map)
    current_file = Keyword.get(opts, :current_file)

    if link_map do
      # Use page mentions for resolved internal links
      case LinkMap.resolve_for_notion(link_map, href, current_file: current_file) do
        {:page_mention, page_id} ->
          # Get link text for the mention content
          text = flatten_text(children)
          [RichText.page_mention(text, page_id)]

        {:link, resolved_href} ->
          children
          |> children_to_rich_text(opts)
          |> Enum.map(&add_link(&1, resolved_href))
      end
    else
      # No link_map - keep as regular link
      children
      |> children_to_rich_text(opts)
      |> Enum.map(&add_link(&1, href))
    end
  end

  defp node_to_rich_text({"del", _, children, _}, opts) do
    children
    |> children_to_rich_text(opts)
    |> Enum.map(&add_annotation(&1, :strikethrough))
  end

  defp node_to_rich_text({"br", _, _, _}, _opts) do
    [RichText.text("\n")]
  end

  defp node_to_rich_text(_, _opts), do: []

  # Annotation helpers

  defp add_annotation(%RichText{} = rt, :bold), do: %{rt | bold: true}
  defp add_annotation(%RichText{} = rt, :italic), do: %{rt | italic: true}
  defp add_annotation(%RichText{} = rt, :strikethrough), do: %{rt | strikethrough: true}

  defp add_link(%RichText{} = rt, href) when is_binary(href) do
    %{rt | link: href, href: href}
  end

  defp add_link(rt, _), do: rt

  # Table conversion

  defp convert_table(children, opts) do
    {thead_rows, tbody_rows} = extract_table_parts(children)
    all_rows = thead_rows ++ tbody_rows

    case all_rows do
      [] ->
        []

      rows ->
        table_width = get_table_width(rows)

        row_blocks =
          Enum.map(rows, fn {"tr", _, cells, _} ->
            cell_rich_texts =
              Enum.map(cells, fn {_tag, _, cell_children, _} ->
                children_to_rich_text(cell_children, opts)
              end)

            NotionBlock.table_row(cell_rich_texts)
          end)

        [NotionBlock.table(table_width, row_blocks, has_column_header: thead_rows != [])]
    end
  end

  defp extract_table_parts(children) do
    thead =
      children
      |> Enum.filter(fn {tag, _, _, _} -> tag == "thead" end)
      |> Enum.flat_map(fn {"thead", _, rows, _} -> rows end)

    tbody =
      children
      |> Enum.filter(fn {tag, _, _, _} -> tag == "tbody" end)
      |> Enum.flat_map(fn {"tbody", _, rows, _} -> rows end)

    {thead, tbody}
  end

  defp get_table_width([]), do: 0
  defp get_table_width([{"tr", _, cells, _} | _]), do: length(cells)

  # Chunking and splitting

  defp chunk_blocks(blocks) do
    Enum.chunk_every(blocks, @max_blocks_per_chunk)
  end

  defp split_paragraph_blocks(rich_text) do
    total_length =
      Enum.reduce(rich_text, 0, fn rt, acc ->
        acc + String.length(rt.content || "")
      end)

    if total_length <= @max_text_length do
      [NotionBlock.paragraph(rich_text)]
    else
      split_rich_text(rich_text, @max_text_length)
      |> Enum.map(&NotionBlock.paragraph/1)
    end
  end

  defp split_rich_text(rich_text, max_length) do
    {chunks, current, _len} =
      Enum.reduce(rich_text, {[], [], 0}, fn rt, {chunks, current, current_len} ->
        rt_len = String.length(rt.content || "")

        if current_len + rt_len > max_length and current != [] do
          # Start a new chunk
          {[Enum.reverse(current) | chunks], [rt], rt_len}
        else
          {chunks, [rt | current], current_len + rt_len}
        end
      end)

    # Don't forget the last chunk
    all_chunks =
      if current != [] do
        [Enum.reverse(current) | chunks]
      else
        chunks
      end

    Enum.reverse(all_chunks)
  end

  # Helper functions

  defp extract_standalone_image([{"img", _, _, _} = img]), do: {:ok, img}
  defp extract_standalone_image(_), do: :not_image

  defp separate_inline_and_nested(children) do
    {inline, nested} =
      Enum.split_with(children, fn
        {"ul", _, _, _} -> false
        {"ol", _, _, _} -> false
        _ -> true
      end)

    {inline, nested}
  end

  defp extract_language(attrs) do
    case get_attr(attrs, "class") do
      nil -> "plain text"
      class -> class |> String.replace_prefix("language-", "")
    end
  end

  defp get_attr(attrs, key) do
    case Enum.find(attrs, fn {k, _v} -> k == key end) do
      {_, v} -> v
      nil -> nil
    end
  end

  defp flatten_text(children) do
    children
    |> Enum.map(fn
      text when is_binary(text) -> text
      {_, _, nested, _} -> flatten_text(nested)
    end)
    |> Enum.join("")
  end

  defp merge_adjacent_text(rich_texts) do
    # Merge adjacent plain text with same annotations
    # Don't merge mentions or items with different types
    rich_texts
    |> Enum.reduce([], fn rt, acc ->
      case acc do
        [prev | rest]
        when prev.type == "text" and rt.type == "text" and
               prev.bold == rt.bold and prev.italic == rt.italic and
               prev.code == rt.code and prev.link == rt.link ->
          merged = %{prev | content: prev.content <> rt.content}
          [merged | rest]

        _ ->
          [rt | acc]
      end
    end)
    |> Enum.reverse()
  end
end
