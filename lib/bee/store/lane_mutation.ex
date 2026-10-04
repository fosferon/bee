defmodule Bee.Store.LaneMutation do
  @moduledoc """
  Internal owner command for a small, closed set of lane-bound Bee issue writes.
  Repo owns admission, the transaction and publication of graph changes. This
  adapter receipt is not a Workbench command ledger or an abandonment proof.
  """
  @fields ~w(command_id lane_id principal_ref action issue_id body)a
  @updates ~w(title description status priority close_reason)a

  def schema do
    """
    CREATE TABLE lane_mutation_receipts (
      command_id TEXT PRIMARY KEY, principal_ref TEXT NOT NULL,
      lane_id TEXT NOT NULL, issue_id TEXT NOT NULL REFERENCES issues(id),
      request_digest TEXT NOT NULL, action TEXT NOT NULL,
      event_seq INTEGER NOT NULL, applied_at TEXT NOT NULL
    )
    """
  end

  def validate(attrs) when is_map(attrs) do
    if Enum.sort(Map.keys(attrs)) == Enum.sort(@fields) and
         Enum.all?(
           [attrs.command_id, attrs.lane_id, attrs.principal_ref, attrs.issue_id],
           &bounded?/1
         ) and
         is_map(attrs.body) and valid_body?(attrs.action, attrs.body),
       do: :ok,
       else: {:error, :invalid_lane_mutation}
  end

  def validate(_), do: {:error, :invalid_lane_mutation}

  def authorize(check, principal, lane) when is_function(check, 0) do
    case check.() do
      {:ok, %{principal_ref: ^principal, lane_id: ^lane}} -> :ok
      {:error, _} = error -> error
      _ -> {:error, :lane_mutation_not_admitted}
    end
  end

  def authorize(_, _, _), do: {:error, :lane_mutation_not_admitted}

  def apply_command(conn, attrs) do
    with :ok <- validate(attrs),
         {:ok, prior} <- read_receipt(conn, attrs.command_id) do
      case prior do
        nil ->
          apply_new(conn, attrs)

        %{principal_ref: principal} when principal != attrs.principal_ref ->
          {:error, :non_disclosing_conflict}

        %{request_digest: digest} = prior ->
          if digest == digest(attrs),
            do: {:ok, %{receipt: prior, replayed: true}},
            else: {:error, :lane_mutation_conflict}
      end
    end
  end

  def reconcile(conn, command, principal) do
    with {:ok, %{principal_ref: ^principal} = receipt} <- read_receipt(conn, command),
         {:ok, rows} <-
           query(conn, "SELECT MAX(seq) FROM events WHERE issue_id = ?", [receipt.issue_id]),
         {:ok, links} <-
           query(
             conn,
             "SELECT lane_id FROM lane_issue_links WHERE issue_id = ? AND lane_id = ?",
             [receipt.issue_id, receipt.lane_id]
           ) do
      current =
        if rows == [[receipt.event_seq]] and links == [[receipt.lane_id]],
          do: :matching,
          else: :stale

      {:ok, %{receipt: receipt, current: current}}
    else
      {:ok, nil} -> {:error, :receipt_not_found}
      {:ok, _} -> {:error, :non_disclosing_conflict}
      {:error, _} = error -> error
    end
  end

  defp apply_new(conn, attrs) do
    with {:ok, links} <-
           query(
             conn,
             "SELECT lane_id FROM lane_issue_links WHERE issue_id = ? ORDER BY lane_id",
             [attrs.issue_id]
           ),
         :ok <- single_lane_target(links, attrs.lane_id),
         :ok <- mutate(conn, attrs),
         {:ok, seq} <-
           Bee.Store.Events.record(conn, attrs.issue_id, "lane.issue.command_applied",
             actor: attrs.principal_ref,
             fields: %{command_id: attrs.command_id, lane_id: attrs.lane_id, action: attrs.action}
           ),
         now = DateTime.utc_now() |> DateTime.to_iso8601(),
         :ok <-
           exec(
             conn,
             "INSERT INTO lane_mutation_receipts(command_id,principal_ref,lane_id,issue_id,request_digest,action,event_seq,applied_at) VALUES (?,?,?,?,?,?,?,?)",
             [
               attrs.command_id,
               attrs.principal_ref,
               attrs.lane_id,
               attrs.issue_id,
               digest(attrs),
               attrs.action,
               seq,
               now
             ]
           ),
         {:ok, receipt} <- read_receipt(conn, attrs.command_id) do
      {:ok, %{receipt: receipt, replayed: false}}
    else
      {:ok, []} -> {:error, :lane_issue_not_associated}
      {:error, _} = error -> error
    end
  end

  defp single_lane_target([[lane]], lane), do: :ok
  defp single_lane_target([], _), do: {:error, :lane_issue_not_associated}
  defp single_lane_target(_, _), do: {:error, :cross_lane_mutation_requires_gateway}

  def validate_reconciliation(command, principal, lane) do
    if Enum.all?([command, principal, lane], &bounded?/1),
      do: :ok,
      else: {:error, :invalid_lane_mutation}
  end

  defp mutate(conn, %{action: "comment", issue_id: id, body: body, principal_ref: principal}),
    do:
      exec(conn, "INSERT INTO comments(issue_id,body,author,created_at) VALUES (?,?,?,?)", [
        id,
        body["text"],
        principal,
        DateTime.utc_now() |> DateTime.to_iso8601()
      ])

  defp mutate(conn, %{action: "update", issue_id: id, body: body}) do
    pairs = Enum.sort(body)
    {columns, values} = Enum.unzip(pairs)
    setters = Enum.map_join(columns, ",", &(&1 <> " = ?"))
    # Identifiers came only from the closed @updates vocabulary above.
    exec(conn, "UPDATE issues SET " <> setters <> " WHERE id = ?", values ++ [id])
  end

  defp mutate(conn, %{action: "unlock", issue_id: id}), do: Bee.Lock.release(conn, id)

  defp mutate(conn, %{action: "assign", issue_id: id, body: body}),
    do: exec(conn, "UPDATE issues SET assigned_to = ? WHERE id = ?", [body["agent_id"], id])

  defp valid_body?("comment", %{"text" => text} = body),
    do:
      map_size(body) == 1 and is_binary(text) and byte_size(text) in 1..65_536 and
        String.valid?(text)

  defp valid_body?("unlock", body), do: body == %{}

  defp valid_body?("assign", %{"agent_id" => agent} = body),
    do: map_size(body) == 1 and bounded?(agent)

  defp valid_body?("update", body) do
    map_size(body) > 0 and
      Enum.all?(body, fn {key, value} ->
        key in Enum.map(@updates, &Atom.to_string/1) and
          ((key == "priority" and is_integer(value) and value in 0..100) or
             (key != "priority" and is_binary(value) and byte_size(value) <= 65_536 and
                String.valid?(value)))
      end)
  end

  defp valid_body?(_, _), do: false

  defp bounded?(value),
    do:
      is_binary(value) and byte_size(value) in 1..256 and String.valid?(value) and
        String.trim(value) == value

  defp digest(attrs) do
    # Closed scalar fields and sorted body pairs produce an unambiguous stable
    # adapter-local binding; this is not the G0/G2 envelope canonicalization.
    values =
      Enum.map(@fields, fn key ->
        value = Map.fetch!(attrs, key)
        {Atom.to_string(key), if(is_map(value), do: Enum.sort(value), else: value)}
      end)

    :crypto.hash(:sha256, :erlang.term_to_binary(values)) |> Base.encode16(case: :lower)
  end

  defp read_receipt(conn, command) do
    with {:ok, rows} <-
           query(
             conn,
             "SELECT principal_ref,lane_id,issue_id,request_digest,action,event_seq,applied_at FROM lane_mutation_receipts WHERE command_id = ?",
             [command]
           ) do
      case rows do
        [] ->
          {:ok, nil}

        [[principal, lane, issue, digest, action, seq, at]] ->
          {:ok,
           %{
             command_id: command,
             principal_ref: principal,
             lane_id: lane,
             issue_id: issue,
             request_digest: digest,
             action: action,
             event_seq: seq,
             applied_at: at
           }}

        _ ->
          {:error, :lane_mutation_indeterminate}
      end
    end
  end

  defp exec(conn, sql, params), do: with({:ok, []} <- query(conn, sql, params), do: :ok)

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
      {:error, reason} -> {:error, {:lane_mutation_indeterminate, reason}}
    end
  end
end
