defmodule Bee.Store.LaneAssociation do
  @moduledoc false

  @spec valid?(map()) :: boolean()
  def valid?(
        %{command_id: command, lane_id: lane, issue_id: issue, role: role, project_id: project} =
          attrs
      ) do
    map_size(attrs) == 5 and Enum.all?([command, lane, issue], &bounded_id?/1) and
      role in ["root", "member"] and (is_nil(project) or bounded_id?(project))
  end

  def valid?(_), do: false

  # This is a Bee issue link, not an assignment to a Bee project. All reads and
  # writes use Repo's writer connection, inside Repo's BEGIN IMMEDIATE transaction.
  @spec associate(Exqlite.Sqlite3.db(), map()) :: {:ok, map()} | {:error, term()}
  def associate(conn, attrs) do
    with {:ok, receipt} <- receipt(conn, attrs.command_id) do
      if same?(receipt, attrs), do: {:ok, receipt}, else: {:error, :association_conflict}
    else
      {:error, :not_found} -> create(conn, attrs)
      {:error, _} = error -> error
    end
  end

  @spec reconcile(Exqlite.Sqlite3.db(), String.t()) ::
          {:ok, %{receipt: map(), current: :matching | :stale}} | {:error, term()}
  def reconcile(conn, command_id) do
    with {:ok, receipt} <- receipt(conn, command_id),
         {:ok, link} <-
           one(conn, "SELECT role FROM lane_issue_links WHERE lane_id = ? AND issue_id = ?", [
             receipt.lane_id,
             receipt.issue_id
           ]),
         {:ok, issue} <-
           one(conn, "SELECT project_id FROM issues WHERE id = ?", [receipt.issue_id]) do
      current =
        if link == [receipt.role] and issue == [receipt.project_id],
          do: :matching,
          else: :stale

      {:ok, %{receipt: receipt, current: current}}
    else
      {:error, _} = error -> error
    end
  end

  defp create(conn, attrs) do
    with {:ok, [project]} <-
           one(conn, "SELECT project_id FROM issues WHERE id = ?", [attrs.issue_id]),
         true <- project == attrs.project_id,
         {:ok, link} <-
           one(conn, "SELECT role FROM lane_issue_links WHERE lane_id = ? AND issue_id = ?", [
             attrs.lane_id,
             attrs.issue_id
           ]),
         :ok <- compatible_link(link, attrs),
         :ok <- root_available(conn, attrs),
         :ok <- insert_link(conn, link, attrs),
         receipt = Map.put(attrs, :created_at, DateTime.utc_now() |> DateTime.to_iso8601()),
         {:ok, seq} <-
           Bee.Store.Events.record(conn, attrs.issue_id, "lane.issue.associated",
             fields: Map.take(attrs, [:command_id, :lane_id, :role, :project_id])
           ),
         receipt = Map.put(receipt, :event_seq, seq),
         :ok <-
           exec(
             conn,
             "INSERT INTO lane_issue_receipts (command_id, lane_id, issue_id, role, project_id, event_seq, created_at) VALUES (?, ?, ?, ?, ?, ?, ?)",
             [
               receipt.command_id,
               receipt.lane_id,
               receipt.issue_id,
               receipt.role,
               receipt.project_id,
               receipt.event_seq,
               receipt.created_at
             ]
           ) do
      {:ok, receipt}
    else
      false -> {:error, :association_conflict}
      {:ok, nil} -> {:error, :issue_not_found}
      {:error, :not_found} -> {:error, :issue_not_found}
      {:error, _} = error -> error
    end
  end

  defp compatible_link(nil, _attrs), do: :ok
  defp compatible_link([role], %{role: role}), do: :ok
  defp compatible_link(_, _), do: {:error, :association_conflict}

  defp root_available(_conn, %{role: "member"}), do: :ok

  defp root_available(conn, attrs) do
    case one(conn, "SELECT issue_id FROM lane_issue_links WHERE lane_id = ? AND role = 'root'", [
           attrs.lane_id
         ]) do
      {:ok, nil} -> :ok
      {:ok, [issue]} when issue == attrs.issue_id -> :ok
      {:ok, _} -> {:error, :association_conflict}
      {:error, _} = error -> error
    end
  end

  defp insert_link(_conn, [_role], _attrs), do: :ok

  defp insert_link(conn, nil, attrs) do
    exec(conn, "INSERT INTO lane_issue_links (lane_id, issue_id, role) VALUES (?, ?, ?)", [
      attrs.lane_id,
      attrs.issue_id,
      attrs.role
    ])
  end

  defp receipt(conn, command_id) do
    case one(
           conn,
           "SELECT lane_id, issue_id, role, project_id, event_seq, created_at FROM lane_issue_receipts WHERE command_id = ?",
           [
             command_id
           ]
         ) do
      {:ok, nil} ->
        {:error, :not_found}

      {:ok, [lane, issue, role, project, seq, created]} ->
        {:ok,
         %{
           command_id: command_id,
           lane_id: lane,
           issue_id: issue,
           role: role,
           project_id: project,
           event_seq: seq,
           created_at: created
         }}

      other ->
        other
    end
  end

  defp same?(receipt, attrs),
    do: Map.take(receipt, [:command_id, :lane_id, :issue_id, :role, :project_id]) == attrs

  defp bounded_id?(value),
    do:
      is_binary(value) and byte_size(value) in 1..256 and String.valid?(value) and
        String.trim(value) == value

  defp one(conn, sql, params) do
    with {:ok, stmt} <- Exqlite.Sqlite3.prepare(conn, sql) do
      try do
        with :ok <- Exqlite.Sqlite3.bind(stmt, params) do
          case Exqlite.Sqlite3.step(conn, stmt) do
            {:row, row} -> {:ok, row}
            :done -> {:ok, nil}
            {:error, _} = error -> error
          end
        end
      after
        Exqlite.Sqlite3.release(conn, stmt)
      end
    end
  end

  defp exec(conn, sql, params) do
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
end
