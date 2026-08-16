defmodule Bee.Store.Events do
  @moduledoc false

  @max_value_bytes 2_048

  @spec record(Exqlite.Sqlite3.db(), String.t(), String.t(), keyword()) ::
          {:ok, pos_integer()} | {:error, term()}
  def record(conn, issue_id, event_type, opts \\ []) do
    now = now_iso()

    with {:ok, seq} <- next_sequence(conn, issue_id),
         {:ok, payload} <- payload(opts, seq),
         :ok <-
           execute(
             conn,
             """
             INSERT INTO events (issue_id, seq, event_type, payload, actor, created_at)
             VALUES (?, ?, ?, ?, ?, ?)
             """,
             [
               issue_id,
               seq,
               event_type,
               Jason.encode!(payload),
               Keyword.get(opts, :actor),
               now
             ]
           ),
         :ok <- execute(conn, "UPDATE issues SET updated_at = ? WHERE id = ?", [now, issue_id]) do
      {:ok, seq}
    end
  end

  defp payload(opts, seq) do
    fields =
      opts
      |> Keyword.get(:fields, %{})
      |> resolve_fields(seq)
      |> stringify_map()
      |> truncate_values()

    refs = opts |> Keyword.get(:refs, %{}) |> stringify_map()
    rejected = opts |> Keyword.get(:rejected, %{}) |> stringify_map()
    {:ok, %{fields: fields, refs: refs, rejected: rejected}}
  end

  defp resolve_fields(fields, seq) when is_function(fields, 1), do: fields.(seq)
  defp resolve_fields(fields, _seq), do: fields

  defp next_sequence(conn, issue_id) do
    {:ok, stmt} =
      Exqlite.Sqlite3.prepare(
        conn,
        "SELECT COALESCE(MAX(seq), 0) + 1 FROM events WHERE issue_id = ?"
      )

    :ok = Exqlite.Sqlite3.bind(stmt, [issue_id])

    try do
      case Exqlite.Sqlite3.step(conn, stmt) do
        {:row, [seq]} -> {:ok, seq}
        {:error, reason} -> {:error, reason}
        :done -> {:error, :sequence_unavailable}
      end
    after
      Exqlite.Sqlite3.release(conn, stmt)
    end
  end

  defp execute(conn, sql, params) do
    {:ok, stmt} = Exqlite.Sqlite3.prepare(conn, sql)
    :ok = Exqlite.Sqlite3.bind(stmt, params)

    try do
      case Exqlite.Sqlite3.step(conn, stmt) do
        :done -> :ok
        {:error, reason} -> {:error, reason}
      end
    after
      Exqlite.Sqlite3.release(conn, stmt)
    end
  end

  defp stringify_map(map) when is_map(map),
    do: Map.new(map, fn {key, value} -> {to_string(key), value} end)

  defp stringify_map(_other), do: %{}

  defp truncate_values(map), do: Map.new(map, fn {key, value} -> {key, truncate(value)} end)

  defp truncate(value) do
    encoded = Jason.encode!(value)

    if byte_size(encoded) > @max_value_bytes do
      %{
        "_truncated" => true,
        "sha256" => :crypto.hash(:sha256, encoded) |> Base.encode16(case: :lower),
        "bytes" => byte_size(encoded),
        "preview" => valid_utf8_prefix(encoded, @max_value_bytes)
      }
    else
      value
    end
  end

  defp valid_utf8_prefix(value, max_bytes) do
    value
    |> binary_part(0, min(byte_size(value), max_bytes))
    |> trim_invalid_suffix()
  end

  defp trim_invalid_suffix(value) do
    if byte_size(value) == 0 or String.valid?(value) do
      value
    else
      value
      |> binary_part(0, byte_size(value) - 1)
      |> trim_invalid_suffix()
    end
  end

  defp now_iso, do: DateTime.utc_now() |> DateTime.to_iso8601()
end
