defmodule ArcaNotionex.Schemas.Frontmatter do
  @moduledoc """
  Ecto schema for YAML frontmatter in markdown files.

  Expected format:
  ```yaml
  ---
  title: "Page Title"
  notion_id: abc123-def456-ghi789
  notion_synced_at: 2024-01-07T10:30:00Z
  ---
  ```
  """
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{
          title: String.t() | nil,
          notion_id: String.t() | nil,
          notion_synced_at: DateTime.t() | nil
        }

  @primary_key false
  embedded_schema do
    field(:title, :string)
    field(:notion_id, :string)
    field(:notion_synced_at, :utc_datetime)
  end

  @doc """
  Creates a changeset for frontmatter validation.
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(struct \\ %__MODULE__{}, params) do
    struct
    |> cast(params, [:title, :notion_id, :notion_synced_at])
  end

  @doc """
  Creates a new Frontmatter struct from a map.
  """
  @spec new(map()) :: {:ok, t()} | {:error, Ecto.Changeset.t()}
  def new(params \\ %{}) do
    %__MODULE__{}
    |> changeset(params)
    |> apply_action(:insert)
  end

  @doc """
  Creates a new Frontmatter struct, raising on error.
  """
  @spec new!(map()) :: t()
  def new!(params \\ %{}) do
    case new(params) do
      {:ok, struct} -> struct
      {:error, changeset} -> raise "Invalid frontmatter: #{inspect(changeset.errors)}"
    end
  end
end
