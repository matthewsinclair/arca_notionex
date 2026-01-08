defmodule ArcaNotionex.Schemas.RichText do
  @moduledoc """
  Ecto schema for Notion rich text objects.

  Notion rich text format:
  ```json
  {
    "type": "text",
    "text": { "content": "Hello", "link": null },
    "annotations": {
      "bold": false,
      "italic": false,
      "strikethrough": false,
      "underline": false,
      "code": false,
      "color": "default"
    },
    "plain_text": "Hello",
    "href": null
  }
  ```
  """
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{
          type: String.t(),
          content: String.t(),
          link: String.t() | nil,
          bold: boolean(),
          italic: boolean(),
          strikethrough: boolean(),
          underline: boolean(),
          code: boolean(),
          color: String.t(),
          href: String.t() | nil
        }

  @primary_key false
  embedded_schema do
    field(:type, :string, default: "text")
    field(:content, :string, default: "")
    field(:link, :string)
    field(:bold, :boolean, default: false)
    field(:italic, :boolean, default: false)
    field(:strikethrough, :boolean, default: false)
    field(:underline, :boolean, default: false)
    field(:code, :boolean, default: false)
    field(:color, :string, default: "default")
    field(:href, :string)
  end

  @doc """
  Creates a changeset for rich text validation.
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(struct \\ %__MODULE__{}, params) do
    struct
    |> cast(params, [
      :type,
      :content,
      :link,
      :bold,
      :italic,
      :strikethrough,
      :underline,
      :code,
      :color,
      :href
    ])
    |> validate_required([:content])
  end

  @doc """
  Creates a new RichText struct from a map.
  """
  @spec new(map()) :: {:ok, t()} | {:error, Ecto.Changeset.t()}
  def new(params \\ %{}) do
    %__MODULE__{}
    |> changeset(params)
    |> apply_action(:insert)
  end

  @doc """
  Creates a plain text RichText struct.
  """
  @spec text(String.t()) :: t()
  def text(content) do
    %__MODULE__{type: "text", content: content}
  end

  @doc """
  Creates a bold text RichText struct.
  """
  @spec bold(String.t()) :: t()
  def bold(content) do
    %__MODULE__{type: "text", content: content, bold: true}
  end

  @doc """
  Creates an italic text RichText struct.
  """
  @spec italic(String.t()) :: t()
  def italic(content) do
    %__MODULE__{type: "text", content: content, italic: true}
  end

  @doc """
  Creates an inline code RichText struct.
  """
  @spec code(String.t()) :: t()
  def code(content) do
    %__MODULE__{type: "text", content: content, code: true}
  end

  @doc """
  Creates a linked text RichText struct.
  """
  @spec link(String.t(), String.t()) :: t()
  def link(content, url) do
    %__MODULE__{type: "text", content: content, link: url, href: url}
  end

  @doc """
  Parses a list of Notion API rich_text objects into RichText structs.
  """
  @spec from_notion([map()]) :: [t()]
  def from_notion(rich_text_array) when is_list(rich_text_array) do
    Enum.map(rich_text_array, &parse_rich_text/1)
  end

  @doc """
  Parses a single Notion API rich_text object into a RichText struct.
  """
  @spec parse_rich_text(map()) :: t()
  def parse_rich_text(%{"type" => type} = rt) do
    content = extract_content(rt, type)
    link = extract_link(rt, type)
    annotations = rt["annotations"] || %{}

    %__MODULE__{
      type: type,
      content: content,
      link: link,
      bold: annotations["bold"] || false,
      italic: annotations["italic"] || false,
      strikethrough: annotations["strikethrough"] || false,
      underline: annotations["underline"] || false,
      code: annotations["code"] || false,
      color: annotations["color"] || "default",
      href: rt["href"]
    }
  end

  def parse_rich_text(_), do: %__MODULE__{}

  defp extract_content(rt, "text"), do: get_in(rt, ["text", "content"]) || ""
  defp extract_content(rt, "mention"), do: rt["plain_text"] || ""
  defp extract_content(rt, "equation"), do: get_in(rt, ["equation", "expression"]) || ""
  defp extract_content(rt, _), do: rt["plain_text"] || ""

  defp extract_link(rt, "text") do
    case get_in(rt, ["text", "link", "url"]) do
      nil -> nil
      url -> url
    end
  end

  defp extract_link(_, _), do: nil

  @doc """
  Converts the RichText struct to Notion API format.
  """
  @spec to_notion(t()) :: map()
  def to_notion(%__MODULE__{} = rt) do
    %{
      "type" => rt.type,
      "text" => %{
        "content" => rt.content,
        "link" => if(rt.link, do: %{"url" => rt.link}, else: nil)
      },
      "annotations" => %{
        "bold" => rt.bold,
        "italic" => rt.italic,
        "strikethrough" => rt.strikethrough,
        "underline" => rt.underline,
        "code" => rt.code,
        "color" => rt.color
      },
      "plain_text" => rt.content,
      "href" => rt.href
    }
  end
end
