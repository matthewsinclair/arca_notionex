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

  When body is provided, also computes and stores the content hash for
  incremental sync support.
  """
  @spec set_notion_id(String.t(), String.t(), String.t() | nil) ::
          :ok | {:error, atom(), String.t()}
  def set_notion_id(file_path, notion_id, body \\ nil) do
    updates = %{notion_id: notion_id, notion_synced_at: DateTime.utc_now()}

    updates =
      case body do
        nil -> updates
        content -> Map.put(updates, :content_hash, compute_hash(content))
      end

    update_file(file_path, updates)
  end

  @doc """
  Updates the sync timestamp and content hash in a file's frontmatter.
  """
  @spec update_synced_at(String.t(), String.t() | nil) :: :ok | {:error, atom(), String.t()}
  def update_synced_at(file_path, body \\ nil) do
    updates = %{notion_synced_at: DateTime.utc_now()}

    updates =
      case body do
        nil -> updates
        content -> Map.put(updates, :content_hash, compute_hash(content))
      end

    update_file(file_path, updates)
  end

  @doc """
  Computes SHA-256 hash of content for change detection.

  Returns hash with "sha256:" prefix for future extensibility.

  ## Examples

      iex> Frontmatter.compute_hash("Hello world")
      "sha256:64ec88ca00b268e5ba1a35678a1b5316d212f4f366b2477232534a8aeca37f3c"
  """
  @spec compute_hash(String.t()) :: String.t()
  def compute_hash(content) do
    hash =
      :crypto.hash(:sha256, content)
      |> Base.encode16(case: :lower)

    "sha256:#{hash}"
  end

  @doc """
  Checks if content has changed since last sync.

  Returns true if content differs from stored hash, or if no hash is stored.

  ## Examples

      iex> stored = Frontmatter.compute_hash("old content")
      iex> Frontmatter.content_changed?("new content", stored)
      true

      iex> stored = Frontmatter.compute_hash("same")
      iex> Frontmatter.content_changed?("same", stored)
      false
  """
  @spec content_changed?(String.t(), String.t() | nil) :: boolean()
  def content_changed?(_current_content, nil), do: true

  def content_changed?(current_content, stored_hash) do
    compute_hash(current_content) != stored_hash
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
    file_path
    |> File.read()
    |> handle_file_read(file_path)
  end

  defp handle_file_read({:ok, content}, file_path) do
    content
    |> parse()
    |> handle_parsed_content(file_path)
  end

  defp handle_file_read({:error, reason}, _file_path) do
    {:error, :file_error, "Failed to read file: #{reason}"}
  end

  defp handle_parsed_content({:ok, %FrontmatterSchema{title: title}, _body}, _file_path)
       when is_binary(title) and title != "" and title != "Index" do
    {:already_has_title, title}
  end

  defp handle_parsed_content({:ok, frontmatter, body}, file_path) do
    derived_title = derive_title_from_path(file_path)
    title = select_title(extract_title_from_content(body), derived_title)
    updated = %{frontmatter | title: title}
    new_content = serialize(updated) <> body
    File.write(file_path, new_content)
  end

  defp handle_parsed_content({:error, type, msg}, _file_path) do
    {:error, type, msg}
  end

  defp select_title(nil, derived), do: derived
  defp select_title("Index", derived), do: derived
  defp select_title(heading, _derived), do: heading

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

  @doc """
  Derives a title from file path with smart handling for index.md files.

  - Regular files: humanize filename (my-doc.md -> "My Doc")
  - index.md: use parent directory name (arch/index.md -> "Arch")
  - Root index.md: keeps "Index"

  ## Examples

      iex> Frontmatter.derive_title_from_path("docs/architecture/index.md")
      "Architecture"

      iex> Frontmatter.derive_title_from_path("index.md")
      "Index"

      iex> Frontmatter.derive_title_from_path("my-great-doc.md")
      "My Great Doc"
  """
  @spec derive_title_from_path(String.t()) :: String.t()
  def derive_title_from_path(file_path) do
    file_path
    |> Path.basename(".md")
    |> derive_title_from_basename(file_path)
  end

  defp derive_title_from_basename("index", file_path) do
    file_path
    |> Path.dirname()
    |> Path.basename()
    |> derive_title_for_index()
  end

  defp derive_title_from_basename(basename, _file_path), do: humanize_name(basename)

  defp derive_title_for_index("."), do: "Index"
  defp derive_title_for_index(parent_dir), do: humanize_name(parent_dir)

  defp extract_title_from_content(body) do
    case Regex.run(~r/^#\s+(.+)$/m, body) do
      [_, title] -> String.trim(title)
      nil -> nil
    end
  end

  defp humanize_name(name) do
    name
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
      notion_synced_at: parse_datetime(Map.get(yaml_map, "notion_synced_at")),
      content_hash: Map.get(yaml_map, "content_hash")
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
    Enum.reduce(updates, fm, &apply_update/2)
  end

  defp apply_update({:title, value}, acc), do: %{acc | title: value}
  defp apply_update({:notion_id, value}, acc), do: %{acc | notion_id: value}
  defp apply_update({:notion_synced_at, value}, acc), do: %{acc | notion_synced_at: value}
  defp apply_update({:content_hash, value}, acc), do: %{acc | content_hash: value}
  defp apply_update({"title", value}, acc), do: %{acc | title: value}
  defp apply_update({"notion_id", value}, acc), do: %{acc | notion_id: value}
  defp apply_update({"notion_synced_at", value}, acc), do: %{acc | notion_synced_at: value}
  defp apply_update({"content_hash", value}, acc), do: %{acc | content_hash: value}
  defp apply_update({_key, _value}, acc), do: acc

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
