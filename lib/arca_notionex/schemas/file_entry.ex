defmodule ArcaNotionex.Schemas.FileEntry do
  @moduledoc """
  Ecto schema for file entries discovered during directory scanning.

  Used to track files and their position in the directory hierarchy.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias ArcaNotionex.Schemas.Frontmatter

  @type t :: %__MODULE__{
          path: String.t(),
          relative_path: String.t(),
          depth: non_neg_integer(),
          parent_path: String.t() | nil,
          filename: String.t(),
          frontmatter: Frontmatter.t() | nil
        }

  @primary_key false
  embedded_schema do
    field(:path, :string)
    field(:relative_path, :string)
    field(:depth, :integer, default: 0)
    field(:parent_path, :string)
    field(:filename, :string)
    embeds_one(:frontmatter, Frontmatter)
  end

  @doc """
  Creates a changeset for file entry validation.
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(struct \\ %__MODULE__{}, params) do
    struct
    |> cast(params, [:path, :relative_path, :depth, :parent_path, :filename])
    |> cast_embed(:frontmatter)
    |> validate_required([:path, :relative_path, :filename])
  end

  @doc """
  Creates a new FileEntry from a file path.
  """
  @spec new(String.t(), String.t()) :: t()
  def new(path, base_path) do
    relative = Path.relative_to(path, base_path)
    parts = Path.split(relative)

    %__MODULE__{
      path: path,
      relative_path: relative,
      depth: length(parts) - 1,
      parent_path: parent_path(parts),
      filename: List.last(parts)
    }
  end

  @doc """
  Creates a new FileEntry with frontmatter.
  """
  @spec with_frontmatter(t(), Frontmatter.t()) :: t()
  def with_frontmatter(%__MODULE__{} = entry, %Frontmatter{} = frontmatter) do
    %{entry | frontmatter: frontmatter}
  end

  @doc """
  Returns the title from frontmatter or filename.
  """
  @spec title(t()) :: String.t()
  def title(%__MODULE__{frontmatter: %Frontmatter{title: title}})
      when is_binary(title) and title != "" do
    title
  end

  def title(%__MODULE__{filename: filename}) do
    filename
    |> Path.rootname()
    |> String.replace(~r/[-_]/, " ")
    |> String.split()
    |> Enum.map(&String.capitalize/1)
    |> Enum.join(" ")
  end

  @doc """
  Returns the notion_id from frontmatter if present.
  """
  @spec notion_id(t()) :: String.t() | nil
  def notion_id(%__MODULE__{frontmatter: %Frontmatter{notion_id: id}}) when is_binary(id), do: id
  def notion_id(_), do: nil

  @doc """
  Returns true if the file has a notion_id.
  """
  @spec has_notion_id?(t()) :: boolean()
  def has_notion_id?(entry), do: notion_id(entry) != nil

  # Private helpers

  defp parent_path([_single]), do: nil

  defp parent_path(parts) do
    parts
    |> Enum.drop(-1)
    |> Path.join()
  end
end
