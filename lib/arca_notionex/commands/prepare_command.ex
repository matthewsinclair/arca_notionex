defmodule ArcaNotionex.Commands.PrepareCommand do
  @moduledoc """
  Command to prepare markdown files for Notion sync by adding frontmatter.
  """
  use Arca.Cli.Command.BaseCommand

  alias ArcaNotionex.Frontmatter

  config :prepare,
    name: "prepare",
    about: "Add frontmatter to markdown files for Notion sync",
    help: """
    Prepares markdown files for Notion sync by adding YAML frontmatter.
    Extracts the title from the first # heading in each file.

    Required:
      --dir        Directory containing markdown files

    Optional:
      --dry-run    Show what would be done without making changes

    Example:
      notionex prepare --dir ./docs
      notionex prepare --dir ./docs --dry-run
    """,
    options: [
      dir: [
        long: "--dir",
        short: "-d",
        help: "Directory containing markdown files",
        parser: :string,
        required: true
      ]
    ],
    flags: [
      dry_run: [
        long: "--dry-run",
        help: "Preview changes without modifying files",
        default: false
      ]
    ]

  @impl Arca.Cli.Command.CommandBehaviour
  def handle(args, _settings, _optimus) do
    dir = get_option(args, :dir)
    dry_run = get_flag(args, :dry_run)

    files =
      dir
      |> Path.join("**/*.md")
      |> Path.wildcard()
      |> Enum.sort()

    if dry_run do
      show_dry_run(files, dir)
    else
      process_files(files, dir)
    end
  end

  defp get_option(%{options: opts}, key), do: Map.get(opts, key)
  defp get_flag(%{flags: flags}, key), do: Map.get(flags, key, false)

  defp show_dry_run(files, base_dir) do
    results =
      Enum.map(files, fn path ->
        rel_path = Path.relative_to(path, base_dir)

        case File.read(path) do
          {:ok, content} ->
            case Frontmatter.parse(content) do
              {:ok, %{title: title}, _} when is_binary(title) and title != "" ->
                {rel_path, :has_title, title}

              {:ok, _, body} ->
                title = extract_title(body, path)
                {rel_path, :would_add, title}

              {:error, _, _} ->
                {rel_path, :error, "Parse error"}
            end

          {:error, reason} ->
            {rel_path, :error, "Read error: #{reason}"}
        end
      end)

    {has_title, needs_update, errors} =
      Enum.reduce(results, {[], [], []}, fn
        {path, :has_title, title}, {h, n, e} -> {[{path, title} | h], n, e}
        {path, :would_add, title}, {h, n, e} -> {h, [{path, title} | n], e}
        {path, :error, msg}, {h, n, e} -> {h, n, [{path, msg} | e]}
      end)

    output = ["[DRY RUN] Would prepare #{length(files)} files:\n"]

    output =
      if length(needs_update) > 0 do
        lines =
          needs_update
          |> Enum.reverse()
          |> Enum.map(fn {path, title} -> "  + #{path} (title: \"#{title}\")" end)

        output ++ ["Would add frontmatter to #{length(needs_update)} files:"] ++ lines ++ [""]
      else
        output
      end

    output =
      if length(has_title) > 0 do
        lines =
          has_title
          |> Enum.reverse()
          |> Enum.take(10)
          |> Enum.map(fn {path, title} -> "  = #{path} (title: \"#{title}\")" end)

        more =
          if length(has_title) > 10, do: ["  ... and #{length(has_title) - 10} more"], else: []

        output ++
          ["Already have frontmatter (#{length(has_title)} files):"] ++ lines ++ more ++ [""]
      else
        output
      end

    output =
      if length(errors) > 0 do
        lines =
          errors
          |> Enum.reverse()
          |> Enum.map(fn {path, msg} -> "  ! #{path}: #{msg}" end)

        output ++ ["Errors (#{length(errors)} files):"] ++ lines ++ [""]
      else
        output
      end

    output =
      output ++
        [
          "Summary: #{length(needs_update)} to add, #{length(has_title)} already done, #{length(errors)} errors"
        ]

    Enum.join(output, "\n")
  end

  defp process_files(files, base_dir) do
    results =
      Enum.map(files, fn path ->
        rel_path = Path.relative_to(path, base_dir)
        result = Frontmatter.ensure_frontmatter(path)
        {rel_path, result}
      end)

    {added, skipped, errors} =
      Enum.reduce(results, {0, 0, []}, fn
        {_, :ok}, {a, s, e} -> {a + 1, s, e}
        {_, {:already_has_title, _}}, {a, s, e} -> {a, s + 1, e}
        {path, {:error, _, msg}}, {a, s, e} -> {a, s, [{path, msg} | e]}
      end)

    output = [
      "Prepare Complete",
      "================",
      "Added frontmatter: #{added}",
      "Already had title: #{skipped}",
      "Errors: #{length(errors)}"
    ]

    output =
      if length(errors) > 0 do
        error_lines = Enum.map(errors, fn {path, msg} -> "  #{path}: #{msg}" end)
        output ++ ["\nErrors:"] ++ error_lines
      else
        output
      end

    Enum.join(output, "\n")
  end

  defp extract_title(body, path) do
    case Regex.run(~r/^#\s+(.+)$/m, body) do
      [_, title] ->
        String.trim(title)

      nil ->
        path
        |> Path.basename(".md")
        |> String.replace(~r/[-_]/, " ")
        |> String.split()
        |> Enum.map(&String.capitalize/1)
        |> Enum.join(" ")
    end
  end
end
