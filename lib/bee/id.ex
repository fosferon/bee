defmodule Bee.Id do
  @moduledoc false

  @type id_input :: String.t() | integer() | nil

  @spec next(Exqlite.Sqlite3.db(), String.t()) :: String.t()
  def next(conn, prefix) do
    sql = """
    INSERT INTO id_counter (prefix, next_id) VALUES (?, 1)
    ON CONFLICT(prefix) DO UPDATE SET next_id = next_id + 1
    RETURNING next_id
    """

    {:ok, stmt} = Exqlite.Sqlite3.prepare(conn, sql)
    :ok = Exqlite.Sqlite3.bind(stmt, [prefix])
    {:row, [id]} = Exqlite.Sqlite3.step(conn, stmt)
    Exqlite.Sqlite3.release(conn, stmt)
    "#{prefix}-#{id}"
  end

  @spec current(Exqlite.Sqlite3.db(), String.t()) :: integer()
  def current(conn, prefix) do
    {:ok, stmt} = Exqlite.Sqlite3.prepare(conn, "SELECT next_id FROM id_counter WHERE prefix = ?")
    :ok = Exqlite.Sqlite3.bind(stmt, [prefix])

    result =
      case Exqlite.Sqlite3.step(conn, stmt) do
        {:row, [id]} -> id - 1
        :done -> 0
      end

    Exqlite.Sqlite3.release(conn, stmt)
    result
  end

  @spec set(Exqlite.Sqlite3.db(), String.t(), integer()) :: :ok
  def set(conn, prefix, value) do
    sql = """
    INSERT INTO id_counter (prefix, next_id) VALUES (?, ?)
    ON CONFLICT(prefix) DO UPDATE SET next_id = excluded.next_id
    """

    {:ok, stmt} = Exqlite.Sqlite3.prepare(conn, sql)
    :ok = Exqlite.Sqlite3.bind(stmt, [prefix, value + 1])
    :done = Exqlite.Sqlite3.step(conn, stmt)
    Exqlite.Sqlite3.release(conn, stmt)
    :ok
  end

  # --- AD-24: single-point id conversion ---

  @doc """
  Parses a prefixed string id to its integer form.

  Accepts:
  - `"GC-805"` → `{:ok, 805}`
  - `805` (already integer) → `{:ok, 805}` (idempotent)

  Rejects:
  - `"GC-"` (prefix only, no number) → `{:error, :invalid_id}`
  - `nil` → `{:error, :invalid_id}`
  - `""` → `{:error, :invalid_id}`
  """
  @spec parse(id_input()) :: {:ok, integer()} | {:error, :invalid_id}
  def parse(nil), do: {:error, :invalid_id}
  def parse(""), do: {:error, :invalid_id}

  def parse(id) when is_integer(id), do: {:ok, id}

  def parse(id) when is_binary(id) do
    case String.split(id, "-") do
      [_prefix, number] when byte_size(number) > 0 ->
        case Integer.parse(number) do
          {n, ""} -> {:ok, n}
          _ -> {:error, :invalid_id}
        end

      _ ->
        {:error, :invalid_id}
    end
  end

  @doc """
  Parses a prefixed string id to its integer form, raising on invalid input.

  Raises `ArgumentError` for malformed ids (AD-25: structural error → raise).
  """
  @spec parse!(id_input()) :: integer()
  def parse!(id) do
    case parse(id) do
      {:ok, n} -> n
      {:error, :invalid_id} -> raise ArgumentError, "invalid id: #{inspect(id)}"
    end
  end

  @doc """
  Converts an integer or bare-number string to a prefixed string id.

  Accepts:
  - `805, "GC"` → `"GC-805"`
  - `"GC-805", "GC"` → `"GC-805"` (already prefixed, idempotent)
  - `"805", "GC"` → `"GC-805"` (bare number string)

  Rejects (raises `ArgumentError`):
  - `nil` → raise
  - `""` → raise
  - `"GC-"` (prefix only) → raise

  Projects and agents use free-form string ids outside this grammar;
  they pass through unchanged when they already contain a hyphen.
  """
  @spec to_prefixed(id_input(), String.t()) :: String.t()
  def to_prefixed(nil, _prefix), do: raise(ArgumentError, "invalid id: nil")
  def to_prefixed("", _prefix), do: raise(ArgumentError, "invalid id: empty string")

  def to_prefixed(id, prefix) when is_integer(id), do: "#{prefix}-#{id}"

  def to_prefixed(id, prefix) when is_binary(id) do
    cond do
      String.contains?(id, "-") ->
        id

      true ->
        case Integer.parse(id) do
          {n, ""} -> "#{prefix}-#{n}"
          _ -> raise ArgumentError, "invalid id: #{inspect(id)}"
        end
    end
  end

  @doc """
  Formats a parent id, returning nil for absent parents.

  Same conversion rules as `to_prefixed/2`, but `nil` and `""` return `nil`
  rather than raising, since an absent parent is not a structural error.
  """
  @spec format_parent(id_input(), String.t()) :: String.t() | nil
  def format_parent(nil, _prefix), do: nil
  def format_parent("", _prefix), do: nil
  def format_parent(parent, prefix), do: to_prefixed(parent, prefix)
end
