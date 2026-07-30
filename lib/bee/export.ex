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
    case File.read(path) do
      {:ok, content} ->
        lines =
          content
          |> String.split("\n", trim: true)
          |> Enum.map(&Jason.decode!/1)

        max_num =
          Enum.reduce(lines, 0, fn data, acc ->
            num = extract_num(Map.get(data, "id", ""))
            max(acc, num)
          end)

        # idempotent import via upsert — re-importing the same
        # trail changes nothing (Story 3.4, FR16).
        Enum.each(lines, fn data ->
          id = Map.get(data, "id")

          attrs = %{
            id: id,
            title: Map.get(data, "title"),
            description: Map.get(data, "description"),
            status: Map.get(data, "status", "open"),
            priority: Map.get(data, "priority"),
            issue_type: Map.get(data, "issue_type", "task"),
            project_id: Map.get(data, "project_id"),
            assigned_to: Map.get(data, "assigned_to"),
            labels: Map.get(data, "labels", []),
            created_at: Map.get(data, "created_at"),
            created_by: Map.get(data, "created_by"),
            closed_at: Map.get(data, "closed_at"),
            close_reason: Map.get(data, "close_reason")
          }

          {:ok, _} = Bee.Store.upsert_issue(conn, attrs)

          # Replace comments: delete existing, insert from JSONL
          Bee.Store.delete_comments(conn, id)

          Enum.each(Map.get(data, "comments", []), fn c ->
            Bee.Store.insert_comment(conn, id, Map.get(c, "text", ""),
              author: Map.get(c, "author")
            )
          end)

          Enum.each(Map.get(data, "dependencies", []), fn dep ->
            depends_on = Map.get(dep, "depends_on_id")

            with true <- is_binary(depends_on),
                 {:ok, type} <-
                   Bee.Dependency.Type.from_storage_name(Map.get(dep, "type", "blocks")) do
              Bee.Store.insert_dependency(conn, id, depends_on, type)
            else
              false -> :ok
              {:error, _reason} -> :ok
            end
          end)
        end)

        if max_num > 0, do: Bee.Id.set(conn, prefix, max_num)

        {:ok, length(lines)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp extract_num(id) do
    case Bee.Id.parse(id) do
      {:ok, n} -> n
      {:error, :invalid_id} -> 0
    end
  end
end
