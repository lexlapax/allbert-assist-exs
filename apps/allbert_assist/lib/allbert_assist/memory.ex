defmodule AllbertAssist.Memory do
  @moduledoc """
  Markdown-first memory store for the v0.01 local assistant loop.

  Markdown files are the source of truth. Runtime/indexed views can grow later,
  but M5 keeps writes and reads simple, inspectable, and portable.
  """

  @categories [:notes, :preferences, :traces, :skills]
  @default_limit 5

  @type category :: :notes | :preferences | :traces | :skills

  @type entry :: %{
          path: String.t(),
          category: category(),
          timestamp: String.t(),
          source_signal_id: String.t(),
          actor: String.t(),
          agent: String.t(),
          summary: String.t(),
          body: String.t()
        }

  @doc "Return supported markdown memory categories."
  @spec categories() :: [category()]
  def categories, do: @categories

  @doc """
  Return the memory root.

  Precedence:

  1. `config :allbert_assist, AllbertAssist.Memory, root: "..."`
  2. `ALLBERT_MEMORY_ROOT`
  3. `var/allbert/memory` under the current project
  """
  @spec root() :: String.t()
  def root do
    configured_root =
      :allbert_assist
      |> Application.get_env(__MODULE__, [])
      |> Keyword.get(:root)

    configured_root || System.get_env("ALLBERT_MEMORY_ROOT") ||
      Path.expand("var/allbert/memory", File.cwd!())
  end

  @doc "Create the memory root and all initial category directories."
  @spec ensure_root!() :: String.t()
  def ensure_root! do
    root = root()

    Enum.each(@categories, fn category ->
      root
      |> Path.join(Atom.to_string(category))
      |> File.mkdir_p!()
    end)

    root
  end

  @doc "Append one markdown memory entry."
  @spec append(map()) :: {:ok, entry()} | {:error, term()}
  def append(attrs) when is_map(attrs) do
    with {:ok, category} <- normalize_category(Map.get(attrs, :category, :notes)),
         {:ok, body} <- normalize_body(Map.get(attrs, :body)),
         {:ok, entry} <- build_entry(attrs, category, body),
         :ok <- write_entry(entry) do
      {:ok, entry}
    end
  end

  def append(_attrs), do: {:error, :invalid_memory_attrs}

  @doc "Read recent markdown memory entries, optionally ranked by query terms."
  @spec recent(keyword()) :: {:ok, [entry()]} | {:error, term()}
  def recent(opts \\ []) when is_list(opts) do
    limit = Keyword.get(opts, :limit, @default_limit)
    query = Keyword.get(opts, :query, "")

    entries =
      ensure_root!()
      |> memory_files()
      |> Enum.flat_map(&read_entry/1)
      |> rank_entries(query)
      |> Enum.take(limit)

    {:ok, entries}
  end

  defp normalize_category(category) when category in @categories, do: {:ok, category}

  defp normalize_category(category) when is_binary(category) do
    category
    |> String.to_existing_atom()
    |> normalize_category()
  rescue
    ArgumentError -> {:error, {:invalid_category, category}}
  end

  defp normalize_category(category), do: {:error, {:invalid_category, category}}

  defp normalize_body(body) when is_binary(body) do
    case String.trim(body) do
      "" -> {:error, :empty_memory}
      body -> {:ok, body}
    end
  end

  defp normalize_body(_body), do: {:error, :missing_memory}

  defp build_entry(attrs, category, body) do
    timestamp = DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
    summary = summarize(Map.get(attrs, :summary) || body)
    actor = Map.get(attrs, :actor, "local") |> to_string()
    agent = Map.get(attrs, :agent, "AllbertAssist.Agents.IntentAgent") |> to_string()
    source_signal_id = Map.get(attrs, :source_signal_id, "unknown") |> to_string()
    channel = Map.get(attrs, :channel, "unknown") |> to_string()
    path = entry_path(category, timestamp, summary)

    {:ok,
     %{
       path: path,
       category: category,
       timestamp: timestamp,
       source_signal_id: source_signal_id,
       actor: actor,
       agent: agent,
       channel: channel,
       summary: summary,
       body: body
     }}
  end

  defp write_entry(entry) do
    entry.path
    |> Path.dirname()
    |> File.mkdir_p!()

    File.write(entry.path, render_entry(entry))
  end

  defp render_entry(entry) do
    """
    # Memory: #{entry.summary}

    - Timestamp: #{entry.timestamp}
    - Category: #{entry.category}
    - Source signal: #{entry.source_signal_id}
    - Actor: #{entry.actor}
    - Agent: #{entry.agent}
    - Channel: #{entry.channel}

    ## Body

    #{entry.body}
    """
    |> String.trim()
    |> Kernel.<>("\n")
  end

  defp entry_path(category, timestamp, summary) do
    filename =
      "#{timestamp_slug(timestamp)}-#{slug(summary)}-#{System.unique_integer([:positive])}.md"

    root()
    |> Path.join(Atom.to_string(category))
    |> Path.join(filename)
  end

  defp memory_files(root) do
    @categories
    |> Enum.flat_map(fn category ->
      root
      |> Path.join(Atom.to_string(category))
      |> Path.join("*.md")
      |> Path.wildcard()
    end)
    |> Enum.sort(:desc)
  end

  defp read_entry(path) do
    case File.read(path) do
      {:ok, content} -> [parse_entry(path, content)]
      {:error, _reason} -> []
    end
  end

  defp parse_entry(path, content) do
    %{
      path: path,
      category: category_from_path(path),
      timestamp: metadata(content, "Timestamp"),
      source_signal_id: metadata(content, "Source signal"),
      actor: metadata(content, "Actor"),
      agent: metadata(content, "Agent"),
      channel: metadata(content, "Channel"),
      summary: summary_from_content(content),
      body: body_from_content(content),
      content: content
    }
  end

  defp category_from_path(path) do
    path
    |> Path.dirname()
    |> Path.basename()
    |> String.to_existing_atom()
  rescue
    ArgumentError -> :notes
  end

  defp metadata(content, key) do
    case Regex.run(~r/^- #{Regex.escape(key)}: (.+)$/m, content) do
      [_, value] -> String.trim(value)
      _match -> ""
    end
  end

  defp summary_from_content(content) do
    case Regex.run(~r/^# Memory: (.+)$/m, content) do
      [_, summary] -> String.trim(summary)
      _match -> ""
    end
  end

  defp body_from_content(content) do
    case String.split(content, "## Body", parts: 2) do
      [_prefix, body] -> String.trim(body)
      _other -> ""
    end
  end

  defp rank_entries(entries, query) do
    tokens = query_tokens(query)

    entries
    |> Enum.map(&{score_entry(&1, tokens), &1})
    |> Enum.sort_by(fn {score, entry} -> {score, entry.timestamp, entry.path} end, :desc)
    |> Enum.map(fn {_score, entry} -> entry end)
  end

  defp score_entry(_entry, []), do: 0

  defp score_entry(entry, tokens) do
    haystack =
      [entry.summary, entry.body, Atom.to_string(entry.category)]
      |> Enum.join(" ")
      |> String.downcase()

    Enum.count(tokens, &String.contains?(haystack, &1))
  end

  defp query_tokens(query) when is_binary(query) do
    query
    |> String.downcase()
    |> String.split(~r/[^a-z0-9]+/, trim: true)
    |> Enum.reject(&(&1 in ["what", "do", "you", "remember", "about", "my", "the", "a", "an"]))
  end

  defp query_tokens(_query), do: []

  defp summarize(text) do
    text
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
    |> String.slice(0, 96)
  end

  defp slug(text) do
    text
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, "-")
    |> String.trim("-")
    |> String.slice(0, 48)
    |> case do
      "" -> "memory"
      slug -> slug
    end
  end

  defp timestamp_slug(timestamp) do
    String.replace(timestamp, ~r/[^0-9A-Za-z]+/, "-")
  end
end
