defmodule ArcaNotionex.BlocksFromNotion do
  @moduledoc """
  Parses Notion API block responses into NotionBlock structs.

  This is the inverse of `NotionBlock.to_notion/1` - it takes raw JSON
  from the Notion API and converts it to typed Ecto structs.

  ## Supported Block Types

  - paragraph
  - heading_1, heading_2, heading_3
  - bulleted_list_item, numbered_list_item
  - code
  - quote
  - table, table_row

  Unsupported block types are skipped with a warning logged.

  ## Example

      blocks = [
        %{"type" => "paragraph", "paragraph" => %{"rich_text" => [...]}},
        %{"type" => "heading_1", "heading_1" => %{"rich_text" => [...]}}
      ]

      {:ok, parsed} = BlocksFromNotion.parse(blocks)
      # [%NotionBlock{type: :paragraph, ...}, %NotionBlock{type: :heading_1, ...}]

  """

  alias ArcaNotionex.Schemas.{NotionBlock, RichText}

  @type parse_opts :: [fetch_children: boolean()]
  @type parse_result :: {:ok, [NotionBlock.t()]} | {:error, atom(), String.t()}

  @supported_types ~w(paragraph heading_1 heading_2 heading_3 bulleted_list_item numbered_list_item code quote table table_row)

  @doc """
  Parses a list of raw Notion block maps into NotionBlock structs.

  ## Options

  - `:fetch_children` - If true, recursively parse inline children.
                        Default: true (uses children already in the response)

  ## Examples

      iex> blocks = [%{"type" => "paragraph", "paragraph" => %{"rich_text" => []}}]
      iex> {:ok, [block]} = BlocksFromNotion.parse(blocks)
      iex> block.type
      :paragraph

  """
  @spec parse([map()], parse_opts()) :: parse_result()
  def parse(blocks, opts \\ []) when is_list(blocks) do
    results =
      blocks
      |> Enum.map(fn block -> parse_block(block, opts) end)
      |> Enum.reject(&is_nil/1)

    {:ok, results}
  rescue
    e in KeyError ->
      {:error, :malformed_json, "Missing required field: #{inspect(e)}"}
  end

  @doc """
  Parses a single Notion block map into a NotionBlock struct.

  Returns nil for unsupported block types.
  """
  @spec parse_block(map(), parse_opts()) :: NotionBlock.t() | nil
  def parse_block(%{"type" => type} = block, opts) when type in @supported_types do
    data = block[type]

    if data do
      parse_block_by_type(type, data, block, opts)
    else
      nil
    end
  end

  def parse_block(%{"type" => _type}, _opts) do
    # Unsupported block type - skip silently
    nil
  end

  def parse_block(_, _), do: nil

  # Block type parsers

  defp parse_block_by_type("paragraph", data, _block, _opts) do
    %NotionBlock{
      type: :paragraph,
      rich_text: RichText.from_notion(data["rich_text"] || []),
      color: data["color"] || "default"
    }
  end

  defp parse_block_by_type("heading_1", data, _block, _opts) do
    %NotionBlock{
      type: :heading_1,
      rich_text: RichText.from_notion(data["rich_text"] || []),
      color: data["color"] || "default",
      is_toggleable: data["is_toggleable"] || false
    }
  end

  defp parse_block_by_type("heading_2", data, _block, _opts) do
    %NotionBlock{
      type: :heading_2,
      rich_text: RichText.from_notion(data["rich_text"] || []),
      color: data["color"] || "default",
      is_toggleable: data["is_toggleable"] || false
    }
  end

  defp parse_block_by_type("heading_3", data, _block, _opts) do
    %NotionBlock{
      type: :heading_3,
      rich_text: RichText.from_notion(data["rich_text"] || []),
      color: data["color"] || "default",
      is_toggleable: data["is_toggleable"] || false
    }
  end

  defp parse_block_by_type("bulleted_list_item", data, block, opts) do
    children = parse_children(data, block, opts)

    %NotionBlock{
      type: :bulleted_list_item,
      rich_text: RichText.from_notion(data["rich_text"] || []),
      color: data["color"] || "default",
      children: children
    }
  end

  defp parse_block_by_type("numbered_list_item", data, block, opts) do
    children = parse_children(data, block, opts)

    %NotionBlock{
      type: :numbered_list_item,
      rich_text: RichText.from_notion(data["rich_text"] || []),
      color: data["color"] || "default",
      children: children
    }
  end

  defp parse_block_by_type("code", data, _block, _opts) do
    %NotionBlock{
      type: :code,
      rich_text: RichText.from_notion(data["rich_text"] || []),
      language: data["language"] || "plain text"
    }
  end

  defp parse_block_by_type("quote", data, block, opts) do
    children = parse_children(data, block, opts)

    %NotionBlock{
      type: :quote,
      rich_text: RichText.from_notion(data["rich_text"] || []),
      color: data["color"] || "default",
      children: children
    }
  end

  defp parse_block_by_type("table", data, block, opts) do
    # Table children are table_rows
    children = parse_children(data, block, opts)

    %NotionBlock{
      type: :table,
      table_width: data["table_width"],
      has_column_header: data["has_column_header"] || false,
      has_row_header: data["has_row_header"] || false,
      children: children
    }
  end

  defp parse_block_by_type("table_row", data, _block, _opts) do
    # Each cell is an array of rich_text
    cells =
      (data["cells"] || [])
      |> Enum.map(&RichText.from_notion/1)

    %NotionBlock{
      type: :table_row,
      cells: cells
    }
  end

  # Children parsing

  defp parse_children(data, block, opts) do
    # First check inline children in the data
    inline_children = data["children"] || []

    # If block has_children but no inline children, they need to be fetched separately
    # For now, we only parse inline children (fetch_children is for future API calls)
    has_children = block["has_children"] || false

    cond do
      length(inline_children) > 0 ->
        {:ok, parsed} = parse(inline_children, opts)
        parsed

      has_children and Keyword.get(opts, :fetch_children, false) ->
        # Would need to make API call here - for now return empty
        # This is handled by Client.get_page_blocks/1
        []

      true ->
        []
    end
  end
end
