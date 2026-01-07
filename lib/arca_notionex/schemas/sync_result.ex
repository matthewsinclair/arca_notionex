defmodule ArcaNotionex.Schemas.SyncResult do
  @moduledoc """
  Ecto schema for sync operation results.

  Tracks files that were created, updated, skipped, or had errors.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @type sync_error :: %{file: String.t(), reason: String.t()}

  @type t :: %__MODULE__{
          created: [String.t()],
          updated: [String.t()],
          skipped: [String.t()],
          errors: [sync_error()]
        }

  @primary_key false
  embedded_schema do
    field(:created, {:array, :string}, default: [])
    field(:updated, {:array, :string}, default: [])
    field(:skipped, {:array, :string}, default: [])
    field(:errors, {:array, :map}, default: [])
  end

  @doc """
  Creates a changeset for sync result validation.
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(struct \\ %__MODULE__{}, params) do
    struct
    |> cast(params, [:created, :updated, :skipped, :errors])
  end

  @doc """
  Creates a new empty SyncResult.
  """
  @spec new() :: t()
  def new do
    %__MODULE__{}
  end

  @doc """
  Adds a created file to the result.
  """
  @spec add_created(t(), String.t()) :: t()
  def add_created(%__MODULE__{} = result, file) do
    %{result | created: [file | result.created]}
  end

  @doc """
  Adds an updated file to the result.
  """
  @spec add_updated(t(), String.t()) :: t()
  def add_updated(%__MODULE__{} = result, file) do
    %{result | updated: [file | result.updated]}
  end

  @doc """
  Adds a skipped file to the result.
  """
  @spec add_skipped(t(), String.t()) :: t()
  def add_skipped(%__MODULE__{} = result, file) do
    %{result | skipped: [file | result.skipped]}
  end

  @doc """
  Adds an error to the result.
  """
  @spec add_error(t(), String.t(), String.t()) :: t()
  def add_error(%__MODULE__{} = result, file, reason) do
    error = %{file: file, reason: reason}
    %{result | errors: [error | result.errors]}
  end

  @doc """
  Returns total count of all processed files.
  """
  @spec total_count(t()) :: non_neg_integer()
  def total_count(%__MODULE__{} = result) do
    length(result.created) + length(result.updated) + length(result.skipped) +
      length(result.errors)
  end

  @doc """
  Returns true if there were any errors.
  """
  @spec has_errors?(t()) :: boolean()
  def has_errors?(%__MODULE__{} = result) do
    result.errors != []
  end
end
