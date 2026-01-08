defmodule ArcaNotionex.Schemas.ConflictEntry do
  @moduledoc """
  Ecto schema for tracking sync conflicts between local files and Notion pages.

  Used by the pull command to report conflicts that need manual resolution.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @type conflict_type :: :both_modified | :notion_newer | :local_newer

  @type t :: %__MODULE__{
          file: String.t(),
          notion_id: String.t(),
          local_modified_at: DateTime.t() | nil,
          notion_modified_at: DateTime.t() | nil,
          conflict_type: conflict_type()
        }

  @conflict_types ~w(both_modified notion_newer local_newer)a

  @primary_key false
  embedded_schema do
    field(:file, :string)
    field(:notion_id, :string)
    field(:local_modified_at, :utc_datetime)
    field(:notion_modified_at, :utc_datetime)
    field(:conflict_type, Ecto.Enum, values: @conflict_types)
  end

  @doc """
  Creates a changeset for conflict entry validation.
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(struct \\ %__MODULE__{}, params) do
    struct
    |> cast(params, [:file, :notion_id, :local_modified_at, :notion_modified_at, :conflict_type])
    |> validate_required([:file, :conflict_type])
  end

  @doc """
  Creates a new ConflictEntry struct.
  """
  @spec new(String.t(), String.t(), conflict_type(), keyword()) :: t()
  def new(file, notion_id, conflict_type, opts \\ []) do
    %__MODULE__{
      file: file,
      notion_id: notion_id,
      conflict_type: conflict_type,
      local_modified_at: Keyword.get(opts, :local_modified_at),
      notion_modified_at: Keyword.get(opts, :notion_modified_at)
    }
  end

  @doc """
  Formats the conflict for display.
  """
  @spec format(t()) :: String.t()
  def format(%__MODULE__{} = entry) do
    type_msg =
      case entry.conflict_type do
        :both_modified -> "both modified since last sync"
        :notion_newer -> "Notion page is newer"
        :local_newer -> "local file is newer"
      end

    "#{entry.file} - #{type_msg}"
  end
end
