defmodule ArcaNotionex.Schemas.NotionBlock do
  @moduledoc """
  Ecto schema for Notion block objects.

  Supports block types: paragraph, heading_1, heading_2, heading_3,
  bulleted_list_item, numbered_list_item, code, quote, table, table_row.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias ArcaNotionex.Schemas.RichText

  @type block_type ::
          :paragraph
          | :heading_1
          | :heading_2
          | :heading_3
          | :bulleted_list_item
          | :numbered_list_item
          | :code
          | :quote
          | :table
          | :table_row

  @type t :: %__MODULE__{
          type: block_type(),
          rich_text: [RichText.t()],
          children: [t()],
          language: String.t() | nil,
          color: String.t(),
          is_toggleable: boolean(),
          table_width: non_neg_integer() | nil,
          has_column_header: boolean(),
          has_row_header: boolean(),
          cells: [[RichText.t()]] | nil
        }

  @block_types ~w(paragraph heading_1 heading_2 heading_3 bulleted_list_item numbered_list_item code quote table table_row)a

  @primary_key false
  embedded_schema do
    field(:type, Ecto.Enum, values: @block_types)
    embeds_many(:rich_text, RichText)
    embeds_many(:children, __MODULE__)
    field(:language, :string)
    field(:color, :string, default: "default")
    field(:is_toggleable, :boolean, default: false)
    # Table-specific fields
    field(:table_width, :integer)
    field(:has_column_header, :boolean, default: false)
    field(:has_row_header, :boolean, default: false)
    # Table row cells (list of list of RichText)
    field(:cells, {:array, :any}, default: [])
  end

  @doc """
  Creates a changeset for block validation.
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(struct \\ %__MODULE__{}, params) do
    struct
    |> cast(params, [
      :type,
      :language,
      :color,
      :is_toggleable,
      :table_width,
      :has_column_header,
      :has_row_header,
      :cells
    ])
    |> cast_embed(:rich_text)
    |> cast_embed(:children)
    |> validate_required([:type])
  end

  @doc """
  Creates a paragraph block.
  """
  @spec paragraph([RichText.t()]) :: t()
  def paragraph(rich_text) do
    %__MODULE__{type: :paragraph, rich_text: rich_text}
  end

  @doc """
  Creates a heading_1 block.
  """
  @spec heading_1([RichText.t()]) :: t()
  def heading_1(rich_text) do
    %__MODULE__{type: :heading_1, rich_text: rich_text}
  end

  @doc """
  Creates a heading_2 block.
  """
  @spec heading_2([RichText.t()]) :: t()
  def heading_2(rich_text) do
    %__MODULE__{type: :heading_2, rich_text: rich_text}
  end

  @doc """
  Creates a heading_3 block.
  """
  @spec heading_3([RichText.t()]) :: t()
  def heading_3(rich_text) do
    %__MODULE__{type: :heading_3, rich_text: rich_text}
  end

  @doc """
  Creates a bulleted_list_item block.
  """
  @spec bulleted_list_item([RichText.t()], [t()]) :: t()
  def bulleted_list_item(rich_text, children \\ []) do
    %__MODULE__{type: :bulleted_list_item, rich_text: rich_text, children: children}
  end

  @doc """
  Creates a numbered_list_item block.
  """
  @spec numbered_list_item([RichText.t()], [t()]) :: t()
  def numbered_list_item(rich_text, children \\ []) do
    %__MODULE__{type: :numbered_list_item, rich_text: rich_text, children: children}
  end

  @doc """
  Creates a code block.
  """
  @spec code([RichText.t()], String.t()) :: t()
  def code(rich_text, language \\ "plain text") do
    %__MODULE__{type: :code, rich_text: rich_text, language: language}
  end

  @doc """
  Creates a quote block.
  """
  @spec quote([RichText.t()]) :: t()
  def quote(rich_text) do
    %__MODULE__{type: :quote, rich_text: rich_text}
  end

  @doc """
  Creates a table block.
  """
  @spec table(non_neg_integer(), [t()], keyword()) :: t()
  def table(width, rows, opts \\ []) do
    %__MODULE__{
      type: :table,
      table_width: width,
      children: rows,
      has_column_header: Keyword.get(opts, :has_column_header, false),
      has_row_header: Keyword.get(opts, :has_row_header, false)
    }
  end

  @doc """
  Creates a table_row block.
  """
  @spec table_row([[RichText.t()]]) :: t()
  def table_row(cells) do
    %__MODULE__{type: :table_row, cells: cells}
  end

  @doc """
  Converts the NotionBlock struct to Notion API format.
  """
  @spec to_notion(t()) :: map()
  def to_notion(%__MODULE__{type: :table} = block) do
    %{
      "type" => "table",
      "table" => %{
        "table_width" => block.table_width,
        "has_column_header" => block.has_column_header,
        "has_row_header" => block.has_row_header,
        "children" => Enum.map(block.children, &to_notion/1)
      }
    }
  end

  def to_notion(%__MODULE__{type: :table_row} = block) do
    %{
      "type" => "table_row",
      "table_row" => %{
        "cells" =>
          Enum.map(block.cells, fn cell_rich_text ->
            Enum.map(cell_rich_text, &RichText.to_notion/1)
          end)
      }
    }
  end

  def to_notion(%__MODULE__{type: :code} = block) do
    type_str = Atom.to_string(block.type)

    %{
      "type" => type_str,
      type_str => %{
        "rich_text" => Enum.map(block.rich_text, &RichText.to_notion/1),
        "language" => block.language || "plain text",
        "caption" => []
      }
    }
  end

  def to_notion(%__MODULE__{} = block) do
    type_str = Atom.to_string(block.type)

    base = %{
      "type" => type_str,
      type_str => %{
        "rich_text" => Enum.map(block.rich_text, &RichText.to_notion/1),
        "color" => block.color
      }
    }

    # Add children if present
    if block.children != [] do
      put_in(base, [type_str, "children"], Enum.map(block.children, &to_notion/1))
    else
      base
    end
  end
end
