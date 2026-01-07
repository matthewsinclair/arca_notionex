defmodule ArcaNotionex.Schemas.AuditEntry do
  @moduledoc """
  Ecto schema for audit comparison entries.

  Represents the comparison status between a local file and its Notion page.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @type status :: :synced | :stale | :local_only | :notion_only

  @type t :: %__MODULE__{
          file: String.t(),
          title: String.t(),
          local_status: :exists | :missing,
          notion_status: :exists | :missing | :unknown,
          notion_id: String.t() | nil,
          synced_at: DateTime.t() | nil,
          action_needed: :create | :update | :delete | :none
        }

  @local_statuses ~w(exists missing)a
  @notion_statuses ~w(exists missing unknown)a
  @actions ~w(create update delete none)a

  @primary_key false
  embedded_schema do
    field(:file, :string)
    field(:title, :string)
    field(:local_status, Ecto.Enum, values: @local_statuses)
    field(:notion_status, Ecto.Enum, values: @notion_statuses)
    field(:notion_id, :string)
    field(:synced_at, :utc_datetime)
    field(:action_needed, Ecto.Enum, values: @actions)
  end

  @doc """
  Creates a changeset for audit entry validation.
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(struct \\ %__MODULE__{}, params) do
    struct
    |> cast(params, [
      :file,
      :title,
      :local_status,
      :notion_status,
      :notion_id,
      :synced_at,
      :action_needed
    ])
    |> validate_required([:file, :title, :local_status, :notion_status, :action_needed])
  end

  @doc """
  Creates a new AuditEntry struct.
  """
  @spec new(map()) :: {:ok, t()} | {:error, Ecto.Changeset.t()}
  def new(params) do
    %__MODULE__{}
    |> changeset(params)
    |> apply_action(:insert)
  end

  @doc """
  Creates a synced audit entry (file exists locally, page exists in Notion).
  """
  @spec synced(String.t(), String.t(), String.t(), DateTime.t() | nil) :: t()
  def synced(file, title, notion_id, synced_at \\ nil) do
    %__MODULE__{
      file: file,
      title: title,
      local_status: :exists,
      notion_status: :exists,
      notion_id: notion_id,
      synced_at: synced_at,
      action_needed: :none
    }
  end

  @doc """
  Creates a stale audit entry (file modified after last sync).
  """
  @spec stale(String.t(), String.t(), String.t(), DateTime.t() | nil) :: t()
  def stale(file, title, notion_id, synced_at \\ nil) do
    %__MODULE__{
      file: file,
      title: title,
      local_status: :exists,
      notion_status: :exists,
      notion_id: notion_id,
      synced_at: synced_at,
      action_needed: :update
    }
  end

  @doc """
  Creates a local-only audit entry (file exists but no Notion page).
  """
  @spec local_only(String.t(), String.t()) :: t()
  def local_only(file, title) do
    %__MODULE__{
      file: file,
      title: title,
      local_status: :exists,
      notion_status: :missing,
      notion_id: nil,
      synced_at: nil,
      action_needed: :create
    }
  end

  @doc """
  Creates a notion-only audit entry (page exists but no local file).
  """
  @spec notion_only(String.t(), String.t()) :: t()
  def notion_only(notion_id, title) do
    %__MODULE__{
      file: "[orphan page]",
      title: title,
      local_status: :missing,
      notion_status: :exists,
      notion_id: notion_id,
      synced_at: nil,
      action_needed: :delete
    }
  end

  @doc """
  Returns the computed status based on local and notion status.
  """
  @spec status(t()) :: status()
  def status(%__MODULE__{local_status: :exists, notion_status: :exists, action_needed: :none}),
    do: :synced

  def status(%__MODULE__{local_status: :exists, notion_status: :exists, action_needed: :update}),
    do: :stale

  def status(%__MODULE__{local_status: :exists, notion_status: status})
      when status in [:missing, :unknown],
      do: :local_only

  def status(%__MODULE__{local_status: :missing, notion_status: :exists}), do: :notion_only
  def status(_), do: :local_only
end
