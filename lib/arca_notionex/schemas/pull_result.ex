defmodule ArcaNotionex.Schemas.PullResult do
  @moduledoc """
  Ecto schema for tracking pull operation results.

  Records statistics about files created, updated, skipped, conflicts, and errors
  during a pull from Notion to local markdown files.
  """
  use Ecto.Schema

  alias ArcaNotionex.Schemas.ConflictEntry

  @type pull_error :: {String.t(), atom(), String.t()}

  @type t :: %__MODULE__{
          created: [String.t()],
          updated: [String.t()],
          skipped: [String.t()],
          conflicts: [ConflictEntry.t()],
          errors: [pull_error()]
        }

  @primary_key false
  embedded_schema do
    field(:created, {:array, :string}, default: [])
    field(:updated, {:array, :string}, default: [])
    field(:skipped, {:array, :string}, default: [])
    field(:errors, {:array, :any}, default: [])
    embeds_many(:conflicts, ConflictEntry)
  end

  @doc """
  Creates a new empty PullResult.
  """
  @spec new() :: t()
  def new do
    %__MODULE__{}
  end

  @doc """
  Adds a created file to the result.
  """
  @spec add_created(t(), String.t()) :: t()
  def add_created(%__MODULE__{} = result, path) do
    %{result | created: [path | result.created]}
  end

  @doc """
  Adds an updated file to the result.
  """
  @spec add_updated(t(), String.t()) :: t()
  def add_updated(%__MODULE__{} = result, path) do
    %{result | updated: [path | result.updated]}
  end

  @doc """
  Adds a skipped file to the result.
  """
  @spec add_skipped(t(), String.t()) :: t()
  def add_skipped(%__MODULE__{} = result, path) do
    %{result | skipped: [path | result.skipped]}
  end

  @doc """
  Adds a conflict to the result.
  """
  @spec add_conflict(t(), ConflictEntry.t()) :: t()
  def add_conflict(%__MODULE__{} = result, conflict) do
    %{result | conflicts: [conflict | result.conflicts]}
  end

  @doc """
  Adds an error to the result.
  """
  @spec add_error(t(), String.t(), atom(), String.t()) :: t()
  def add_error(%__MODULE__{} = result, path, reason, message) do
    %{result | errors: [{path, reason, message} | result.errors]}
  end

  @doc """
  Merges two PullResults together.
  """
  @spec merge(t(), t()) :: t()
  def merge(%__MODULE__{} = r1, %__MODULE__{} = r2) do
    %__MODULE__{
      created: r1.created ++ r2.created,
      updated: r1.updated ++ r2.updated,
      skipped: r1.skipped ++ r2.skipped,
      conflicts: r1.conflicts ++ r2.conflicts,
      errors: r1.errors ++ r2.errors
    }
  end

  @doc """
  Formats the result for display.
  """
  @spec format(t(), keyword()) :: String.t()
  def format(%__MODULE__{} = result, opts \\ []) do
    dry_run = Keyword.get(opts, :dry_run, false)
    prefix = if dry_run, do: "[DRY RUN] ", else: ""

    lines = [
      "#{prefix}Pull Complete",
      "=============",
      "Created: #{length(result.created)}",
      "Updated: #{length(result.updated)}",
      "Skipped: #{length(result.skipped)}",
      "Conflicts: #{length(result.conflicts)}",
      "Errors:  #{length(result.errors)}"
    ]

    lines = add_conflict_details(lines, result.conflicts)
    lines = add_error_details(lines, result.errors)

    Enum.join(lines, "\n")
  end

  defp add_conflict_details(lines, []), do: lines

  defp add_conflict_details(lines, conflicts) do
    conflict_lines =
      conflicts
      |> Enum.reverse()
      |> Enum.map(&"  #{ConflictEntry.format(&1)}")

    lines ++ ["", "Conflicts (require manual resolution):"] ++ conflict_lines
  end

  defp add_error_details(lines, []), do: lines

  defp add_error_details(lines, errors) do
    error_lines =
      errors
      |> Enum.reverse()
      |> Enum.map(fn {path, _reason, message} -> "  #{path}: #{message}" end)

    lines ++ ["", "Errors:"] ++ error_lines
  end
end
