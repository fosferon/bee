defmodule Bee.Export do
  @moduledoc false

  @spec export(Exqlite.Sqlite3.db(), String.t()) :: :ok
  def export(conn, path) do
    {:ok, issues} = Bee.Store.list_issues_raw(conn)

    lines =
      Enum.map(issues, fn issue ->
        raw_id = issue.id
        comments = Bee.Store.get_comments(conn, raw_id)

        entry = %{
          "id" => raw_id,
          "title" => issue.title,
          "status" => issue.status,
          "priority" => issue.priority,
          "issue_type" => issue.issue_type || "task",
          "created_at" => issue.created_at,
          "created_by" => issue.created_by,
          "updated_at" => issue.updated_at
        }

        entry =
          if issue.description, do: Map.put(entry, "description", issue.description), else: entry

        entry = if issue.closed_at, do: Map.put(entry, "closed_at", issue.closed_at), else: entry

        entry =
          if issue.close_reason,
            do: Map.put(entry, "close_reason", issue.close_reason),
            else: entry

        labels = Bee.Store.get_labels(conn, raw_id)
        entry = if labels != [], do: Map.put(entry, "labels", labels), else: entry

        entry =
          if issue.assigned_to, do: Map.put(entry, "assigned_to", issue.assigned_to), else: entry

        entry =
          if issue.project_id, do: Map.put(entry, "project_id", issue.project_id), else: entry

        dependencies = Bee.Store.get_dependencies(conn, raw_id)

        entry =
          if dependencies != [] do
            deps =
              Enum.map(dependencies, fn dependency ->
                %{
                  "issue_id" => raw_id,
                  "depends_on_id" => dependency.depends_on_id,
                  "type" => dependency.type,
                  "created_at" => dependency.created_at
                }
              end)

            Map.put(entry, "dependencies", deps)
          else
            entry
          end

        entry =
          if comments != [] do
            c =
              Enum.map(comments, fn cm ->
                %{
                  "id" => cm.id,
                  "issue_id" => raw_id,
                  "author" => cm.author,
                  "text" => cm.body,
                  "created_at" => cm.created_at
                }
              end)

            Map.put(entry, "comments", c)
          else
            entry
          end

        Jason.encode!(entry)
      end)

    # atomic write — temp file + rename, so a reader never sees
    # a half-written trail (Story 3.4, FR16).
    path |> Path.dirname() |> File.mkdir_p!()
    tmp_path = path <> ".tmp"
    File.write!(tmp_path, Enum.join(lines, "\n") <> "\n")
    File.rename!(tmp_path, path)
    :ok
  end

  @spec import_jsonl(Exqlite.Sqlite3.db(), String.t(), String.t()) :: {:ok, integer()}
  def import_jsonl(conn, path, prefix) do
    with {:ok, entries} <- read_entries(path), do: import_entries(conn, entries, prefix)
  end

  def read_entries(path) do
    with {:ok, content} <- File.read(path) do
      content
      |> String.split("\n", trim: true)
      |> Enum.reduce_while({:ok, []}, fn line, {:ok, acc} ->
        case Jason.decode(line) do
          {:ok, data} when is_map(data) ->
            if valid_entry?(data),
              do: {:cont, {:ok, [data | acc]}},
              else: {:halt, {:error, :invalid_import}}

          _ ->
            {:halt, {:error, :invalid_import}}
        end
      end)
      |> case do
        {:ok, entries} -> {:ok, Enum.reverse(entries)}
        {:error, _} = error -> error
      end
    end
  end

  defp valid_entry?(data) do
    is_binary(data["id"]) and is_binary(data["title"]) and data["title"] != "" and
      Enum.all?(
        ~w(description status issue_type project_id assigned_to created_at created_by closed_at close_reason),
        fn key -> is_nil(data[key]) or is_binary(data[key]) end
      ) and
      (is_nil(data["priority"]) or is_integer(data["priority"])) and
      (is_nil(data["parent"]) or is_binary(data["parent"])) and
      is_list(Map.get(data, "labels", [])) and
      Enum.all?(Map.get(data, "labels", []), &is_binary/1) and
      is_list(Map.get(data, "comments", [])) and
      Enum.all?(Map.get(data, "comments", []), fn c ->
        is_map(c) and is_binary(Map.get(c, "text", "")) and
          (is_nil(c["author"]) or is_binary(c["author"]))
      end) and
      is_list(Map.get(data, "dependencies", [])) and
      Enum.all?(Map.get(data, "dependencies", []), fn d ->
        is_map(d) and is_binary(d["depends_on_id"]) and is_binary(Map.get(d, "type", "blocks"))
      end)
  end

  def import_entries(conn, lines, prefix) do
    max_num =
      Enum.reduce(lines, 0, fn data, acc ->
        num = extract_num(Map.get(data, "id", ""))
        max(acc, num)
      end)

    with :ok <-
           Enum.reduce_while(lines, :ok, fn data, :ok ->
             case import_entry(conn, data) do
               :ok -> {:cont, :ok}
               {:error, _} = error -> {:halt, error}
             end
           end),
         :ok <- if(max_num > 0, do: Bee.Id.set(conn, prefix, max_num), else: :ok) do
      {:ok, length(lines)}
    end
  end

  defp import_entry(conn, data) do
    id = Map.get(data, "id")

    attrs = %{
      id: id,
      title: data["title"],
      description: data["description"],
      status: Map.get(data, "status", "open"),
      priority: data["priority"],
      issue_type: Map.get(data, "issue_type", "task"),
      project_id: data["project_id"],
      assigned_to: data["assigned_to"],
      labels: Map.get(data, "labels", []),
      parent: data["parent"],
      created_at: data["created_at"],
      created_by: data["created_by"],
      closed_at: data["closed_at"],
      close_reason: data["close_reason"]
    }

    with {:ok, _} <- Bee.Store.upsert_issue(conn, attrs),
         :ok <- Bee.Store.delete_comments(conn, id),
         :ok <- import_comments(conn, id, Map.get(data, "comments", [])),
         :ok <- import_dependencies(conn, id, Map.get(data, "dependencies", [])),
         do: :ok
  end

  defp import_comments(conn, id, comments) when is_list(comments) do
    Enum.reduce_while(comments, :ok, fn comment, :ok ->
      case Bee.Store.insert_comment(conn, id, Map.get(comment, "text", ""),
             author: Map.get(comment, "author")
           ) do
        :ok -> {:cont, :ok}
        {:error, _} = error -> {:halt, error}
      end
    end)
  end

  defp import_comments(_, _, _), do: {:error, :invalid_import}

  defp import_dependencies(conn, id, dependencies) when is_list(dependencies) do
    Enum.reduce_while(dependencies, :ok, fn dep, :ok ->
      result =
        with true <- is_binary(dep["depends_on_id"]) or {:error, :invalid_import},
             {:ok, type} <- Bee.Dependency.Type.from_storage_name(Map.get(dep, "type", "blocks")),
             do: Bee.Store.insert_dependency(conn, id, dep["depends_on_id"], type)

      case result do
        :ok -> {:cont, :ok}
        {:error, _} = error -> {:halt, error}
      end
    end)
  end

  defp import_dependencies(_, _, _), do: {:error, :invalid_import}

  defp extract_num(id) do
    case Bee.Id.parse(id) do
      {:ok, n} -> n
      {:error, :invalid_id} -> 0
    end
  end
end
