defmodule Bee.Query.Candidates do
  @moduledoc false

  @spec for_issue(Exqlite.Sqlite3.db(), String.t()) :: {:ok, [map()]} | {:error, term()}
  def for_issue(conn, issue_id) do
    sql = """
    WITH target AS (
      SELECT project_id FROM issues WHERE id = ?
    ),
    label_matches AS (
      SELECT DISTINCT candidate.issue_id
      FROM issue_labels target_label
      INNER JOIN issue_labels candidate ON candidate.label = target_label.label
      WHERE target_label.issue_id = ? AND candidate.issue_id != ?
    )
    SELECT issues.id,
           CASE WHEN issues.project_id = target.project_id THEN 'same_project' ELSE 'shared_label' END,
           CASE WHEN issues.project_id = target.project_id THEN 0.8 ELSE 0.6 END
    FROM issues
    CROSS JOIN target
    WHERE issues.id != ?
      AND (issues.project_id = target.project_id OR issues.id IN (SELECT issue_id FROM label_matches))
    ORDER BY 3 DESC, issues.id ASC
    LIMIT 10
    """

    {:ok, stmt} = Exqlite.Sqlite3.prepare(conn, sql)
    :ok = Exqlite.Sqlite3.bind(stmt, [issue_id, issue_id, issue_id, issue_id])

    try do
      {:ok, collect(conn, stmt)}
    after
      Exqlite.Sqlite3.release(conn, stmt)
    end
  end

  defp collect(conn, stmt) do
    case Exqlite.Sqlite3.step(conn, stmt) do
      {:row, [id, reason, confidence]} ->
        [
          %{issue_id: Bee.Id.parse!(id), reason: reason, confidence: confidence}
          | collect(conn, stmt)
        ]

      :done ->
        []
    end
  end
end
