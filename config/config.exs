import Config

config :arca_notionex,
  env: config_env(),
  name: "notionex",
  about: "Notion Markdown Sync CLI",
  description: "Sync markdown files to Notion pages",
  version: "0.1.0",
  author: "matts",
  prompt_symbol: ">",
  configurators: [
    ArcaNotionex.Configurator
  ]

config :arca_cli,
  env: config_env(),
  name: "notionex",
  about: "Notion Markdown Sync CLI",
  description: "Sync markdown files to Notion pages",
  version: "0.1.0",
  author: "matts",
  url: "https://github.com/matthewsinclair/arca-notionex",
  prompt_symbol: ">",
  prompt_text: &ArcaNotionex.Prompt.text/1,
  configurators: [
    ArcaNotionex.Configurator
  ]

config :arca_config,
  config_domain: :arca_notionex

import_config "#{config_env()}.exs"
