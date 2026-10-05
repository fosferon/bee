defmodule Bee.Store.RegistryWrites do
  @moduledoc """
  Legacy registry and bulk project writes owned by Bee.Repo. Callers supply
  closed canonical fields and the original row snapshot, never SQL or a
  connection. Repo qualifies targets and compares the snapshot inside
  BEGIN IMMEDIATE before writing.
  This is not a lane command or an authentication boundary.
  """
  @columns ~w(id name path status created_at updated_at description stack domain repo_url canonical_path source last_synced_at metadata)a
  @fields @columns -- [:created_at, :updated_at]
  @select "SELECT #{Enum.join(@columns, ", ")} FROM projects WHERE id = ?"
  @upsert """
  INSERT INTO projects (#{Enum.join(@columns, ", ")})
  VALUES (#{Enum.map_join(@columns, ", ", fn _ -> "?" end)})
  ON CONFLICT(id) DO UPDATE SET
  #{Enum.map_join(@columns -- [:id, :created_at], ", ", &"#{&1} = excluded.#{&1}")}
  """

  def upsert_project(conn, id, entry, expected) when is_binary(id) and is_map(entry) do
    with true <- bounded?(id),
         :ok <- validate_entry(entry, id),
         {:ok, rows} <- query(conn, @select, [id]),
         true <- List.first(rows) == expected do
      now = DateTime.utc_now() |> DateTime.to_iso8601()

      created =
        case rows do
          [row] -> Enum.at(row, 4)
          [] -> now
        end

      entry = entry |> Map.put(:created_at, created) |> Map.put(:updated_at, now)

      with :ok <- run(conn, @upsert, Enum.map(@columns, &Map.fetch!(entry, &1))),
           {:ok, [row]} <- query(conn, @select, [id]),
           do: {:ok, row}
    else
      false -> {:error, :project_version_conflict}
      {:error, _} = error -> error
    end
  end

  def upsert_project(_, _, _, _), do: {:error, :invalid_project_entry}

  defp validate_entry(entry, id) do
    with true <- Enum.sort(Map.keys(entry)) == Enum.sort(@fields),
         true <- entry.id == id,
         true <- Enum.all?(@fields, &(is_nil(entry[&1]) or is_binary(entry[&1]))),
         true <- Enum.all?([:name, :status, :source, :metadata], &is_binary(entry[&1])),
         {:ok, metadata} when is_map(metadata) <- Jason.decode(entry.metadata) do
      :ok
    else
      _ -> {:error, :invalid_project_entry}
    end
  end

  def backfill(conn, rows, run_id, now, prefix) do
    if valid_backfill?(rows, run_id, now, prefix) do
      Enum.reduce_while(rows, {:ok, 0}, fn row, {:ok, count} ->
        id = Bee.Id.to_prefixed(row.id, prefix)

        with :ok <-
               run(
                 conn,
                 "UPDATE issues SET project_id = ?, updated_at = ? WHERE id = ? AND (project_id IS NULL OR trim(project_id) = '')",
                 [row.project_id, now, id]
               ),
             {:ok, [[changed]]} <- query(conn, "SELECT changes()", []) do
          if changed == 0 do
            {:cont, {:ok, count}}
          else
            with :ok <-
                   run(
                     conn,
                     "INSERT INTO issue_project_backfill_log (run_id, issue_id, old_project_id, new_project_id, rule, created_at) VALUES (?, ?, NULL, ?, ?, ?)",
                     [run_id, id, row.project_id, row.rule, now]
                   ),
                 {:ok, _} <-
                   Bee.Store.Events.record(conn, id, "issue.project_backfilled",
                     fields: %{project_id: row.project_id, rule: row.rule, run_id: run_id}
                   ) do
              {:cont, {:ok, count + 1}}
            else
              {:error, _} = error -> {:halt, error}
            end
          end
        else
          {:error, _} = error -> {:halt, error}
        end
      end)
    else
      {:error, :invalid_project_backfill}
    end
  end

  defp valid_backfill?(rows, run_id, now, prefix) do
    is_list(rows) and bounded?(run_id) and is_binary(now) and
      match?({:ok, _, _}, DateTime.from_iso8601(now)) and
      Enum.all?(rows, fn row ->
        is_map(row) and Enum.sort(Map.keys(row)) == [:id, :project_id, :rule] and
          valid_id?(row.id, prefix) and
          bounded?(row.project_id) and bounded?(row.rule)
      end)
  end

  defp valid_id?(id, prefix) when is_binary(id) or is_integer(id),
    do: match?({:ok, n} when n > 0, Bee.Id.parse(Bee.Id.to_prefixed(id, prefix)))

  defp valid_id?(_, _), do: false

  defp bounded?(value), do: is_binary(value) and byte_size(value) in 1..256

  defp run(conn, sql, params) do
    with {:ok, stmt} <- Exqlite.Sqlite3.prepare(conn, sql) do
      try do
        with :ok <- Exqlite.Sqlite3.bind(stmt, params) do
          case Exqlite.Sqlite3.step(conn, stmt) do
            :done -> :ok
            {:error, _} = error -> error
          end
        end
      after
        Exqlite.Sqlite3.release(conn, stmt)
      end
    end
  end

  defp query(conn, sql, params) do
    with {:ok, stmt} <- Exqlite.Sqlite3.prepare(conn, sql) do
      try do
        with :ok <- Exqlite.Sqlite3.bind(stmt, params), do: collect(conn, stmt, [])
      after
        Exqlite.Sqlite3.release(conn, stmt)
      end
    end
  end

  defp collect(conn, stmt, rows) do
    case Exqlite.Sqlite3.step(conn, stmt) do
      {:row, row} -> collect(conn, stmt, [row | rows])
      :done -> {:ok, Enum.reverse(rows)}
      {:error, _} = error -> error
    end
  end
end
