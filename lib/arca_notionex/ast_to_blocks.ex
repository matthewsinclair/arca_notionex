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

  @max_text_length 2000
  @max_blocks_per_chunk 100

  @type earmark_ast :: {String.t(), list(), list(), map()} | String.t()
  @type convert_result :: {:ok, [[NotionBlock.t()]]} | {:error, atom(), String.t()}

  @doc """
  Converts markdown content to Notion blocks.

  Returns `{:ok, chunks}` where chunks is a list of block lists (for API chunking).
  """
  @spec convert(String.t()) :: convert_result()
  def convert(markdown) when is_binary(markdown) do
    case EarmarkParser.as_ast(markdown) do
      {:ok, ast, _deprecation_messages} ->
        blocks =
          ast
          |> Enum.flat_map(&convert_node/1)
          |> chunk_blocks()

        {:ok, blocks}

      {:error, _ast, errors} ->
        {:error, :parse_error, "Markdown parse error: #{inspect(errors)}"}
    end
  end

  @doc """
  Converts a single AST node to Notion block(s).
  """
  @spec convert_node(earmark_ast()) :: [NotionBlock.t()]
  def convert_node({"h1", _attrs, children, _meta}) do
    [NotionBlock.heading_1(children_to_rich_text(children))]
  end

  def convert_node({"h2", _attrs, children, _meta}) do
    [NotionBlock.heading_2(children_to_rich_text(children))]
  end

  def convert_node({"h3", _attrs, children, _meta}) do
    [NotionBlock.heading_3(children_to_rich_text(children))]
  end

  # h4, h5, h6 map to heading_3 (Notion max)
  def convert_node({"h4", _attrs, children, _meta}) do
    [NotionBlock.heading_3(children_to_rich_text(children))]
  end

  def convert_node({"h5", _attrs, children, _meta}) do
    [NotionBlock.heading_3(children_to_rich_text(children))]
  end

  def convert_node({"h6", _attrs, children, _meta}) do
    [NotionBlock.heading_3(children_to_rich_text(children))]
  end

  def convert_node({"p", _attrs, children, _meta}) do
    rich_text = children_to_rich_text(children)
    split_paragraph_blocks(rich_text)
  end

  def convert_node({"ul", _attrs, children, _meta}) do
    Enum.flat_map(children, fn
      {"li", _, li_children, _} ->
        {inline, nested} = separate_inline_and_nested(li_children)
        nested_blocks = Enum.flat_map(nested, &convert_node/1)
        [NotionBlock.bulleted_list_item(children_to_rich_text(inline), nested_blocks)]

      _ ->
        []
    end)
  end

  def convert_node({"ol", _attrs, children, _meta}) do
    Enum.flat_map(children, fn
      {"li", _, li_children, _} ->
        {inline, nested} = separate_inline_and_nested(li_children)
        nested_blocks = Enum.flat_map(nested, &convert_node/1)
        [NotionBlock.numbered_list_item(children_to_rich_text(inline), nested_blocks)]

      _ ->
        []
    end)
  end

  def convert_node({"pre", _attrs, [{"code", code_attrs, [code_text], _}], _meta})
      when is_binary(code_text) do
    language = extract_language(code_attrs)
    [NotionBlock.code([RichText.text(code_text)], language)]
  end

  def convert_node({"pre", _attrs, [{"code", code_attrs, code_children, _}], _meta}) do
    language = extract_language(code_attrs)
    code_text = flatten_text(code_children)
    [NotionBlock.code([RichText.text(code_text)], language)]
  end

  def convert_node({"blockquote", _attrs, children, _meta}) do
    rich_text =
      Enum.flat_map(children, fn
        {"p", _, p_children, _} -> children_to_rich_text(p_children)
        other -> children_to_rich_text([other])
      end)

    [NotionBlock.quote(rich_text)]
  end

  def convert_node({"table", _attrs, children, _meta}) do
    convert_table(children)
  end

  def convert_node({"hr", _attrs, _children, _meta}) do
    # Horizontal rules become divider blocks (not yet supported, skip)
    []
  end

  def convert_node(text) when is_binary(text) do
    trimmed = String.trim(text)

    if trimmed == "" do
      []
    else
      [NotionBlock.paragraph([RichText.text(trimmed)])]
    end
  end

  def convert_node(_unknown) do
    # Skip unsupported nodes
    []
  end

  # Rich text conversion

  @doc """
  Converts AST children to a list of RichText structs.
  """
  @spec children_to_rich_text(list()) :: [RichText.t()]
  def children_to_rich_text(children) do
    children
    |> Enum.flat_map(&node_to_rich_text/1)
    |> merge_adjacent_text()
  end

  defp node_to_rich_text(text) when is_binary(text) do
    [RichText.text(text)]
  end

  defp node_to_rich_text({"strong", _, children, _}) do
    children
    |> children_to_rich_text()
    |> Enum.map(&add_annotation(&1, :bold))
  end

  defp node_to_rich_text({"em", _, children, _}) do
    children
    |> children_to_rich_text()
    |> Enum.map(&add_annotation(&1, :italic))
  end

  defp node_to_rich_text({"code", _, [text], _}) when is_binary(text) do
    [RichText.code(text)]
  end

  defp node_to_rich_text({"a", attrs, children, _}) do
    href = get_attr(attrs, "href")

    children
    |> children_to_rich_text()
    |> Enum.map(&add_link(&1, href))
  end

  defp node_to_rich_text({"del", _, children, _}) do
    children
    |> children_to_rich_text()
    |> Enum.map(&add_annotation(&1, :strikethrough))
  end

  defp node_to_rich_text({"br", _, _, _}) do
    [RichText.text("\n")]
  end

  defp node_to_rich_text(_), do: []

  # Annotation helpers

  defp add_annotation(%RichText{} = rt, :bold), do: %{rt | bold: true}
  defp add_annotation(%RichText{} = rt, :italic), do: %{rt | italic: true}
  defp add_annotation(%RichText{} = rt, :strikethrough), do: %{rt | strikethrough: true}

  defp add_link(%RichText{} = rt, href) when is_binary(href) do
    %{rt | link: href, href: href}
  end

  defp add_link(rt, _), do: rt

  # Table conversion

  defp convert_table(children) do
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
                children_to_rich_text(cell_children)
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
    rich_texts
    |> Enum.reduce([], fn rt, acc ->
      case acc do
        [prev | rest]
        when prev.bold == rt.bold and prev.italic == rt.italic and
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
