defmodule ArcaNotionex.Schemas.ApiResponse do
  @moduledoc """
  Ecto schema for Notion API responses.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{
          object: String.t(),
          id: String.t() | nil,
          title: String.t() | nil,
          url: String.t() | nil,
          created_time: DateTime.t() | nil,
          last_edited_time: DateTime.t() | nil,
          has_more: boolean(),
          next_cursor: String.t() | nil,
          results: [map()]
        }

  @primary_key false
  embedded_schema do
    field(:object, :string)
    field(:id, :string)
    field(:title, :string)
    field(:url, :string)
    field(:created_time, :utc_datetime)
    field(:last_edited_time, :utc_datetime)
    field(:has_more, :boolean, default: false)
    field(:next_cursor, :string)
    field(:results, {:array, :map}, default: [])
  end

  @doc """
  Creates a changeset for API response validation.
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(struct \\ %__MODULE__{}, params) do
    struct
    |> cast(params, [
      :object,
      :id,
      :title,
      :url,
      :created_time,
      :last_edited_time,
      :has_more,
      :next_cursor,
      :results
    ])
  end

  @doc """
  Creates an ApiResponse from a raw Notion API response map.
  """
  @spec from_response(map()) :: t()
  def from_response(response) when is_map(response) do
    %__MODULE__{
      object: Map.get(response, "object"),
      id: Map.get(response, "id"),
      title: extract_title(response),
      url: Map.get(response, "url"),
      created_time: parse_datetime(Map.get(response, "created_time")),
      last_edited_time: parse_datetime(Map.get(response, "last_edited_time")),
      has_more: Map.get(response, "has_more", false),
      next_cursor: Map.get(response, "next_cursor"),
      results: Map.get(response, "results", [])
    }
  end

  @doc """
  Returns true if this is a page response.
  """
  @spec page?(t()) :: boolean()
  def page?(%__MODULE__{object: "page"}), do: true
  def page?(_), do: false

  @doc """
  Returns true if this is a list response.
  """
  @spec list?(t()) :: boolean()
  def list?(%__MODULE__{object: "list"}), do: true
  def list?(_), do: false

  @doc """
  Returns true if there are more results to fetch.
  """
  @spec has_more?(t()) :: boolean()
  def has_more?(%__MODULE__{has_more: true}), do: true
  def has_more?(_), do: false

  # Private helpers

  defp extract_title(%{
         "properties" => %{"title" => %{"title" => [%{"plain_text" => title} | _]}}
       }) do
    title
  end

  defp extract_title(%{"child_page" => %{"title" => title}}) do
    title
  end

  defp extract_title(_), do: nil

  defp parse_datetime(nil), do: nil

  defp parse_datetime(str) when is_binary(str) do
    case DateTime.from_iso8601(str) do
      {:ok, dt, _offset} -> dt
      {:error, _} -> nil
    end
  end

  defp parse_datetime(_), do: nil
end
