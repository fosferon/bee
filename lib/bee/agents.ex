defmodule Bee.Agents do
  @moduledoc false

  @spec insert_project(Exqlite.Sqlite3.db(), String.t(), map()) :: {:ok, map()}
  def insert_project(conn, id, attrs \\ %{}) do
    now = now_iso()

    if Map.has_key?(attrs, :metadata) do
      run_sql(
        conn,
        """
        INSERT INTO projects (id, name, path, status, created_at, updated_at, metadata)
        VALUES (?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET metadata = excluded.metadata, updated_at = excluded.updated_at
        """,
        [
          id,
          Map.get(attrs, :name, id),
          Map.get(attrs, :path),
          Map.get(attrs, :status, "active"),
          now,
          now,
          Map.fetch!(attrs, :metadata)
        ]
      )
    else
      run_sql(
        conn,
        "INSERT OR IGNORE INTO projects (id, name, path, status, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?)",
        [
          id,
          Map.get(attrs, :name, id),
          Map.get(attrs, :path),
          Map.get(attrs, :status, "active"),
          now,
          now
        ]
      )
    end

    get_project(conn, id)
  end

  @spec get_project(Exqlite.Sqlite3.db(), String.t()) :: {:ok, map()} | {:error, :not_found}
  def get_project(conn, id) do
    {:ok, stmt} = Exqlite.Sqlite3.prepare(conn, "SELECT * FROM projects WHERE id = ?")
    :ok = Exqlite.Sqlite3.bind(stmt, [id])

    case Exqlite.Sqlite3.step(conn, stmt) do
      {:row, row} ->
        {:ok, cols} = Exqlite.Sqlite3.columns(conn, stmt)
        Exqlite.Sqlite3.release(conn, stmt)
        {:ok, row_to_map(cols, row)}

      :done ->
        Exqlite.Sqlite3.release(conn, stmt)
        {:error, :not_found}
    end
  end

  @spec list_projects(Exqlite.Sqlite3.db()) :: {:ok, [map()]}
  def list_projects(conn) do
    {:ok, stmt} =
      Exqlite.Sqlite3.prepare(
        conn,
        """
        SELECT projects.*,
               (SELECT COUNT(*) FROM issues WHERE issues.project_id = projects.id) AS issue_count
        FROM projects
        ORDER BY projects.name
        """
      )

    rows = Bee.Store.collect_rows(conn, stmt)
    Exqlite.Sqlite3.release(conn, stmt)
    {:ok, Enum.map(rows, fn {cols, row} -> row_to_map(cols, row) end)}
  end

  @spec insert_agent(Exqlite.Sqlite3.db(), String.t(), map()) :: {:ok, map()}
  def insert_agent(conn, id, attrs \\ %{}) do
    now = now_iso()
    caps = if Map.get(attrs, :capabilities), do: Jason.encode!(attrs.capabilities), else: nil

    run_sql(
      conn,
      "INSERT OR IGNORE INTO agents (id, name, type, status, capabilities, updated_at) VALUES (?, ?, ?, ?, ?, ?)",
      [
        id,
        Map.get(attrs, :name, id),
        Map.get(attrs, :type, "worker"),
        Map.get(attrs, :status, "idle"),
        caps,
        now
      ]
    )

    get_agent(conn, id)
  end

  @spec get_agent(Exqlite.Sqlite3.db(), String.t()) :: {:ok, map()} | {:error, :not_found}
  def get_agent(conn, id) do
    {:ok, stmt} = Exqlite.Sqlite3.prepare(conn, "SELECT * FROM agents WHERE id = ?")
    :ok = Exqlite.Sqlite3.bind(stmt, [id])

    case Exqlite.Sqlite3.step(conn, stmt) do
      {:row, row} ->
        {:ok, cols} = Exqlite.Sqlite3.columns(conn, stmt)
        Exqlite.Sqlite3.release(conn, stmt)
        {:ok, row_to_map(cols, row)}

      :done ->
        Exqlite.Sqlite3.release(conn, stmt)
        {:error, :not_found}
    end
  end

  @spec update_agent(Exqlite.Sqlite3.db(), String.t(), map()) :: :ok
  def update_agent(conn, id, attrs) do
    sets = ["updated_at = ?"]
    vals = [now_iso()]

    {sets, vals} =
      Enum.reduce([:name, :type, :status], {sets, vals}, fn key, {s, v} ->
        if Map.has_key?(attrs, key),
          do: {["#{key} = ?" | s], [Map.get(attrs, key) | v]},
          else: {s, v}
      end)

    set_clause = sets |> Enum.reverse() |> Enum.join(", ")
    run_sql(conn, "UPDATE agents SET #{set_clause} WHERE id = ?", Enum.reverse(vals) ++ [id])
    :ok
  end

  @spec list_agents(Exqlite.Sqlite3.db()) :: {:ok, [map()]}
  def list_agents(conn) do
    {:ok, stmt} = Exqlite.Sqlite3.prepare(conn, "SELECT * FROM agents ORDER BY name")
    rows = Bee.Store.collect_rows(conn, stmt)
    Exqlite.Sqlite3.release(conn, stmt)
    {:ok, Enum.map(rows, fn {cols, row} -> row_to_map(cols, row) end)}
  end

  @spec add_project_agent(Exqlite.Sqlite3.db(), String.t(), String.t(), String.t()) :: :ok
  def add_project_agent(conn, project_id, agent_id, role \\ "worker") do
    run_sql(
      conn,
      "INSERT OR IGNORE INTO project_agents (project_id, agent_id, role) VALUES (?, ?, ?)",
      [project_id, agent_id, role]
    )

    :ok
  end

  @spec remove_project_agent(Exqlite.Sqlite3.db(), String.t(), String.t()) :: :ok
  def remove_project_agent(conn, project_id, agent_id) do
    run_sql(conn, "DELETE FROM project_agents WHERE project_id = ? AND agent_id = ?", [
      project_id,
      agent_id
    ])

    :ok
  end

  @spec assign_issue(Exqlite.Sqlite3.db(), String.t(), String.t()) :: :ok
  def assign_issue(conn, issue_id, agent_id) do
    run_sql(conn, "UPDATE issues SET assigned_to = ?, updated_at = ? WHERE id = ?", [
      agent_id,
      now_iso(),
      issue_id
    ])

    :ok
  end

  @spec unassign_issue(Exqlite.Sqlite3.db(), String.t()) :: :ok
  def unassign_issue(conn, issue_id) do
    run_sql(conn, "UPDATE issues SET assigned_to = NULL, updated_at = ? WHERE id = ?", [
      now_iso(),
      issue_id
    ])

    :ok
  end

  @spec project_agents(Exqlite.Sqlite3.db(), String.t()) :: [String.t()]
  def project_agents(conn, project_id) do
    {:ok, stmt} =
      Exqlite.Sqlite3.prepare(conn, "SELECT agent_id FROM project_agents WHERE project_id = ?")

    :ok = Exqlite.Sqlite3.bind(stmt, [project_id])
    result = collect_scalars(conn, stmt)
    Exqlite.Sqlite3.release(conn, stmt)
    result
  end

  # --- Helpers ---

  defp run_sql(conn, sql, params) do
    {:ok, stmt} = Exqlite.Sqlite3.prepare(conn, sql)
    :ok = Exqlite.Sqlite3.bind(stmt, params)
    :done = Exqlite.Sqlite3.step(conn, stmt)
    Exqlite.Sqlite3.release(conn, stmt)
    :ok
  end

  defp collect_scalars(conn, stmt) do
    case Exqlite.Sqlite3.step(conn, stmt) do
      {:row, [val]} -> [val | collect_scalars(conn, stmt)]
      :done -> []
    end
  end

  defp row_to_map(cols, row) do
    map = Enum.zip(cols, row) |> Map.new()

    if Map.has_key?(map, "metadata") do
      Map.update!(map, "metadata", &Bee.Store.Metadata.decode/1)
    else
      map
    end
  end

  defp now_iso, do: DateTime.utc_now() |> DateTime.to_iso8601()
end
