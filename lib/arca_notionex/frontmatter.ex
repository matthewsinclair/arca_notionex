defmodule ArcaNotionex.Frontmatter do
  @moduledoc """
  Parses and serializes YAML frontmatter in markdown files.

  Frontmatter is delimited by `---` markers at the start of a file:

  ```markdown
  ---
  title: "Page Title"
  notion_id: abc123-def456
  notion_synced_at: 2024-01-07T10:30:00Z
  ---

  # Content starts here
  ```
  """

  alias ArcaNotionex.Schemas.Frontmatter, as: FrontmatterSchema

  @frontmatter_regex ~r/\A---\n(.*?)\n---\n?(.*)\z/s

  @type parse_result :: {:ok, FrontmatterSchema.t(), String.t()} | {:error, atom(), String.t()}

  @doc """
  Parses frontmatter from markdown content.

  Returns `{:ok, frontmatter_struct, body}` or `{:error, reason, details}`.

  ## Examples

      iex> content = \"\"\"
      ...> ---
      ...> title: "Hello"
      ...> ---
      ...> # Content
      ...> \"\"\"
      iex> {:ok, fm, body} = ArcaNotionex.Frontmatter.parse(content)
      iex> fm.title
      "Hello"
      iex> body
      "# Content\\n"
  """
  @spec parse(String.t()) :: parse_result()
  def parse(content) when is_binary(content) do
    case extract_frontmatter(content) do
      {:ok, yaml_str, body} ->
        parse_yaml(yaml_str, body)

      {:no_frontmatter, body} ->
        {:ok, FrontmatterSchema.new!(), body}
    end
  end

  @doc """
  Serializes a Frontmatter struct to YAML string with delimiters.

  ## Examples

      iex> fm = %ArcaNotionex.Schemas.Frontmatter{title: "Hello", notion_id: "abc123"}
      iex> ArcaNotionex.Frontmatter.serialize(fm)
      "---\\ntitle: \\"Hello\\"\\nnotion_id: \\"abc123\\"\\n---\\n"
  """
  @spec serialize(FrontmatterSchema.t()) :: String.t()
  def serialize(%FrontmatterSchema{} = frontmatter) do
    fields =
      frontmatter
      |> Map.from_struct()
      |> Enum.filter(fn {_k, v} -> v != nil end)
      |> Enum.map(fn {k, v} -> "#{k}: #{format_value(v)}" end)
      |> Enum.join("\n")

    "---\n#{fields}\n---\n"
  end

  @doc """
  Updates the frontmatter in a file.

  Reads the file, updates the frontmatter, and writes it back.
  """
  @spec update_file(String.t(), map()) :: :ok | {:error, atom(), String.t()}
  def update_file(file_path, updates) when is_map(updates) do
    with {:ok, content} <- File.read(file_path),
         {:ok, frontmatter, body} <- parse(content) do
      updated_frontmatter = update_frontmatter(frontmatter, updates)
      new_content = serialize(updated_frontmatter) <> body
      File.write(file_path, new_content)
    else
      {:error, reason} when is_atom(reason) ->
        {:error, :file_error, "Failed to read file: #{reason}"}

      {:error, type, msg} ->
        {:error, type, msg}
    end
  end

  @doc """
  Sets the notion_id in a file's frontmatter.
  """
  @spec set_notion_id(String.t(), String.t()) :: :ok | {:error, atom(), String.t()}
  def set_notion_id(file_path, notion_id) do
    update_file(file_path, %{notion_id: notion_id, notion_synced_at: DateTime.utc_now()})
  end

  @doc """
  Updates the sync timestamp in a file's frontmatter.
  """
  @spec update_synced_at(String.t()) :: :ok | {:error, atom(), String.t()}
  def update_synced_at(file_path) do
    update_file(file_path, %{notion_synced_at: DateTime.utc_now()})
  end

  @doc """
  Ensures a file has frontmatter with at least a title.

  If the file has no frontmatter, adds one with the title extracted from
  the first `# Heading` line, or derived from the filename.

  Returns `:ok` if frontmatter was added/updated, or `{:already_has_title, title}`.
  """
  @spec ensure_frontmatter(String.t()) ::
          :ok | {:already_has_title, String.t()} | {:error, atom(), String.t()}
  def ensure_frontmatter(file_path) do
    case File.read(file_path) do
      {:ok, content} ->
        case parse(content) do
          {:ok, %FrontmatterSchema{title: title}, _body} when is_binary(title) and title != "" ->
            {:already_has_title, title}

          {:ok, frontmatter, body} ->
            title = extract_title_from_content(body) || derive_title_from_path(file_path)
            updated = %{frontmatter | title: title}
            new_content = serialize(updated) <> body
            File.write(file_path, new_content)

          {:error, type, msg} ->
            {:error, type, msg}
        end

      {:error, reason} ->
        {:error, :file_error, "Failed to read file: #{reason}"}
    end
  end

  @doc """
  Ensures frontmatter for all markdown files in a directory.

  Returns a list of `{path, result}` tuples.
  """
  @spec ensure_frontmatter_in_directory(String.t()) :: [
          {String.t(), :ok | {:already_has_title, String.t()} | {:error, atom(), String.t()}}
        ]
  def ensure_frontmatter_in_directory(dir_path) do
    dir_path
    |> Path.join("**/*.md")
    |> Path.wildcard()
    |> Enum.map(fn path ->
      {path, ensure_frontmatter(path)}
    end)
  end

  defp extract_title_from_content(body) do
    case Regex.run(~r/^#\s+(.+)$/m, body) do
      [_, title] -> String.trim(title)
      nil -> nil
    end
  end

  defp derive_title_from_path(file_path) do
    file_path
    |> Path.basename(".md")
    |> String.replace(~r/[-_]/, " ")
    |> String.split()
    |> Enum.map(&String.capitalize/1)
    |> Enum.join(" ")
  end

  # Private functions

  defp extract_frontmatter(content) do
    case Regex.run(@frontmatter_regex, content) do
      [_, yaml, body] -> {:ok, yaml, body}
      nil -> {:no_frontmatter, content}
    end
  end

  defp parse_yaml(yaml_str, body) do
    case YamlElixir.read_from_string(yaml_str) do
      {:ok, yaml_map} when is_map(yaml_map) ->
        frontmatter = build_frontmatter(yaml_map)
        {:ok, frontmatter, body}

      {:ok, _} ->
        # YAML parsed but not a map (e.g., empty or scalar)
        {:ok, FrontmatterSchema.new!(), body}

      {:error, %YamlElixir.ParsingError{} = error} ->
        {:error, :yaml_parse_error, Exception.message(error)}
    end
  end

  defp build_frontmatter(yaml_map) do
    %FrontmatterSchema{
      title: Map.get(yaml_map, "title"),
      notion_id: Map.get(yaml_map, "notion_id"),
      notion_synced_at: parse_datetime(Map.get(yaml_map, "notion_synced_at"))
    }
  end

  defp parse_datetime(nil), do: nil
  defp parse_datetime(%DateTime{} = dt), do: dt

  defp parse_datetime(str) when is_binary(str) do
    case DateTime.from_iso8601(str) do
      {:ok, dt, _offset} -> dt
      {:error, _} -> nil
    end
  end

  defp parse_datetime(_), do: nil

  defp update_frontmatter(%FrontmatterSchema{} = fm, updates) do
    updates
    |> Enum.reduce(fm, fn {key, value}, acc ->
      case key do
        :title -> %{acc | title: value}
        :notion_id -> %{acc | notion_id: value}
        :notion_synced_at -> %{acc | notion_synced_at: value}
        "title" -> %{acc | title: value}
        "notion_id" -> %{acc | notion_id: value}
        "notion_synced_at" -> %{acc | notion_synced_at: value}
        _ -> acc
      end
    end)
  end

  defp format_value(%DateTime{} = dt), do: "\"#{DateTime.to_iso8601(dt)}\""
  defp format_value(str) when is_binary(str), do: "\"#{escape_yaml_string(str)}\""
  defp format_value(nil), do: "null"
  defp format_value(val), do: inspect(val)

  defp escape_yaml_string(str) do
    str
    |> String.replace("\\", "\\\\")
    |> String.replace("\"", "\\\"")
  end
end
