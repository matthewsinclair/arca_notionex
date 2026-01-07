defmodule ArcaNotionex.MixProject do
  use Mix.Project

  def project do
    [
      app: :arca_notionex,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      elixirc_paths: elixirc_paths(Mix.env())
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  def application do
    [
      extra_applications: [:logger],
      mod: {ArcaNotionex.Application, []}
    ]
  end

  defp deps do
    [
      # CLI framework
      {:arca_cli, github: "matthewsinclair/arca-cli", branch: "main", override: true},

      # Markdown parsing
      {:earmark_parser, "~> 1.4"},

      # HTTP client
      {:req, "~> 0.4"},

      # YAML frontmatter parsing
      {:yaml_elixir, "~> 2.9"},

      # Table output
      {:table_rex, "~> 4.0"},

      # JSON encoding/decoding
      {:jason, "~> 1.4"},

      # Ecto for typed schemas (no database)
      {:ecto, "~> 3.11"}
    ]
  end
end
