defmodule ArcaNotionex.Client do
  @moduledoc """
  Notion API client with rate limiting and error handling.

  Respects Notion's API constraints:
  - 3 requests/second rate limit (334ms between requests)
  - 100 blocks per request
  - Handles pagination

  ## Configuration

  Set the `NOTION_API_TOKEN` environment variable or configure in config:

      config :arca_notionex,
        notion_api_token: "secret_xxx"
  """

  alias ArcaNotionex.Schemas.{ApiResponse, NotionBlock}

  @base_url "https://api.notion.com/v1"
  @notion_version "2022-06-28"
  @rate_limit_ms 334

  @type api_result :: {:ok, ApiResponse.t()} | {:error, atom(), String.t()}

  # Public API

  @doc """
  Creates a new page under a parent page.
  """
  @spec create_page(String.t(), String.t(), [NotionBlock.t()]) :: api_result()
  def create_page(parent_id, title, blocks \\ []) do
    body = %{
      "parent" => %{"page_id" => parent_id},
      "properties" => %{
        "title" => [%{"type" => "text", "text" => %{"content" => title}}]
      },
      "children" => blocks_to_notion(blocks) |> Enum.take(100)
    }

    post("/pages", body)
  end

  @doc """
  Updates a page's blocks by clearing and appending new ones.
  """
  @spec update_page_blocks(String.t(), [NotionBlock.t()]) :: api_result()
  def update_page_blocks(page_id, blocks) do
    with {:ok, _} <- clear_page_blocks(page_id) do
      append_blocks(page_id, blocks)
    end
  end

  @doc """
  Appends blocks to a page (in chunks of 100).
  """
  @spec append_blocks(String.t(), [NotionBlock.t()]) :: api_result()
  def append_blocks(page_id, blocks) do
    notion_blocks = blocks_to_notion(blocks)

    notion_blocks
    |> Enum.chunk_every(100)
    |> Enum.reduce_while({:ok, nil}, fn chunk, _acc ->
      case patch("/blocks/#{page_id}/children", %{"children" => chunk}) do
        {:ok, response} -> {:cont, {:ok, response}}
        error -> {:halt, error}
      end
    end)
  end

  @doc """
  Retrieves a page by ID.
  """
  @spec get_page(String.t()) :: api_result()
  def get_page(page_id) do
    get("/pages/#{page_id}")
  end

  @doc """
  Lists child pages under a parent.
  """
  @spec list_child_pages(String.t(), keyword()) :: api_result()
  def list_child_pages(parent_id, opts \\ []) do
    cursor = Keyword.get(opts, :cursor)
    params = [page_size: 100] ++ if(cursor, do: [start_cursor: cursor], else: [])

    case get("/blocks/#{parent_id}/children", params) do
      {:ok, response} ->
        if ApiResponse.has_more?(response) do
          fetch_remaining_pages(response, parent_id)
        else
          {:ok, response}
        end

      error ->
        error
    end
  end

  @doc """
  Retrieves a block by ID.
  """
  @spec get_block(String.t()) :: api_result()
  def get_block(block_id) do
    get("/blocks/#{block_id}")
  end

  @doc """
  Deletes a block by ID.
  """
  @spec delete_block(String.t()) :: api_result()
  def delete_block(block_id) do
    delete("/blocks/#{block_id}")
  end

  # Private HTTP methods

  defp get(path, params \\ []) do
    rate_limit()

    url = @base_url <> path

    case Req.get(url, headers: headers(), params: params) do
      {:ok, response} -> handle_response(response)
      {:error, reason} -> {:error, :network_error, inspect(reason)}
    end
  end

  defp post(path, body) do
    rate_limit()

    url = @base_url <> path

    case Req.post(url, headers: headers(), json: body) do
      {:ok, response} -> handle_response(response)
      {:error, reason} -> {:error, :network_error, inspect(reason)}
    end
  end

  defp patch(path, body) do
    rate_limit()

    url = @base_url <> path

    case Req.patch(url, headers: headers(), json: body) do
      {:ok, response} -> handle_response(response)
      {:error, reason} -> {:error, :network_error, inspect(reason)}
    end
  end

  defp delete(path) do
    rate_limit()

    url = @base_url <> path

    case Req.delete(url, headers: headers()) do
      {:ok, response} -> handle_response(response)
      {:error, reason} -> {:error, :network_error, inspect(reason)}
    end
  end

  defp headers do
    token = get_api_token()

    [
      {"Authorization", "Bearer #{token}"},
      {"Notion-Version", @notion_version},
      {"Content-Type", "application/json"}
    ]
  end

  defp get_api_token do
    System.get_env("NOTION_API_TOKEN") ||
      Application.get_env(:arca_notionex, :notion_api_token) ||
      raise "NOTION_API_TOKEN not configured. Set the environment variable or configure in config.exs"
  end

  defp rate_limit do
    Process.sleep(@rate_limit_ms)
  end

  defp handle_response(%{status: status, body: body}) when status in 200..299 do
    {:ok, ApiResponse.from_response(body)}
  end

  defp handle_response(%{status: 429, body: body}) do
    retry_after = Map.get(body, "retry_after", 1)
    {:error, :rate_limited, "Rate limited. Retry after #{retry_after}s"}
  end

  defp handle_response(%{status: 400, body: body}) do
    message = Map.get(body, "message", "Bad request")
    {:error, :bad_request, message}
  end

  defp handle_response(%{status: 401, body: _body}) do
    {:error, :unauthorized, "Invalid API token"}
  end

  defp handle_response(%{status: 403, body: _body}) do
    {:error, :forbidden, "Access forbidden. Check page permissions."}
  end

  defp handle_response(%{status: 404, body: _body}) do
    {:error, :not_found, "Page or block not found"}
  end

  defp handle_response(%{status: 409, body: body}) do
    message = Map.get(body, "message", "Conflict")
    {:error, :conflict, message}
  end

  defp handle_response(%{status: status, body: body}) do
    message = Map.get(body, "message", "Unknown error")
    {:error, :api_error, "HTTP #{status}: #{message}"}
  end

  # Helper functions

  defp clear_page_blocks(page_id) do
    case get("/blocks/#{page_id}/children") do
      {:ok, response} ->
        response.results
        |> Enum.each(fn block ->
          block_id = Map.get(block, "id")
          if block_id, do: delete_block(block_id)
        end)

        {:ok, :cleared}

      error ->
        error
    end
  end

  defp fetch_remaining_pages(%ApiResponse{} = response, parent_id) do
    if ApiResponse.has_more?(response) do
      case list_child_pages(parent_id, cursor: response.next_cursor) do
        {:ok, next_response} ->
          combined = %{response | results: response.results ++ next_response.results}
          {:ok, combined}

        error ->
          error
      end
    else
      {:ok, response}
    end
  end

  defp blocks_to_notion(blocks) do
    blocks
    |> List.flatten()
    |> Enum.map(&NotionBlock.to_notion/1)
  end
end
