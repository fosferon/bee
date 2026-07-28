defmodule Bee.Store.Measurements do
  @moduledoc false

  @spec register(Exqlite.Sqlite3.db(), String.t(), String.t()) ::
          :ok | {:error, :invalid_measure | :unit_mismatch | term()}
  def register(conn, name, unit), do: register(conn, name, unit, [])

  @spec register(Exqlite.Sqlite3.db(), String.t(), String.t(), keyword()) ::
          :ok
          | {:error,
             :invalid_measure
             | :invalid_measure_domain
             | :unit_mismatch
             | :domain_mismatch
             | term()}
  def register(conn, name, unit, opts)
      when is_binary(name) and name != "" and is_binary(unit) and unit != "" and is_list(opts) do
    with {:ok, domain} <- domain(opts) do
      case registered_measure(conn, name) do
        nil ->
          execute(
            conn,
            "INSERT INTO measures (name, unit, domain, registered_at) VALUES (?, ?, ?, ?)",
            [name, unit, domain, now_iso()]
          )

        %{unit: ^unit, domain: ^domain} ->
          :ok

        %{unit: ^unit} ->
          {:error, :domain_mismatch}

        _other ->
          {:error, :unit_mismatch}
      end
    end
  end

  def register(_conn, _name, _unit, _opts), do: {:error, :invalid_measure}

  defp domain(opts) do
    case Keyword.get(opts, :domain, :any) do
      domain when domain in [:any, :non_negative] -> {:ok, Atom.to_string(domain)}
      _ -> {:error, :invalid_measure_domain}
    end
  end

  @spec prepare(Exqlite.Sqlite3.db(), map()) ::
          {:ok,
           %{
             measure: String.t(),
             value: float(),
             unit: String.t(),
             dims: map(),
             source: String.t() | nil
           }}
          | {:error,
             :unknown_measure
             | :invalid_measure
             | :invalid_dimension_key
             | :invalid_measurement_kind}
  def prepare(conn, attrs) when is_map(attrs) do
    with measure when is_binary(measure) and measure != "" <- fetch(attrs, :measure),
         value when is_number(value) <- fetch(attrs, :value),
         %{unit: unit, domain: domain} <- registered_measure(conn, measure),
         dims when is_map(dims) <- fetch(attrs, :dims, %{}),
         :ok <- validate_dims(dims),
         :ok <- validate_kind(dims),
         :ok <- validate_domain(value, domain) do
      {:ok,
       %{
         measure: measure,
         value: value * 1.0,
         unit: unit,
         dims: dims,
         source: fetch(attrs, :source)
       }}
    else
      nil -> {:error, :unknown_measure}
      {:error, _reason} = error -> error
      _ -> {:error, :invalid_measure}
    end
  end

  def prepare(_conn, _attrs), do: {:error, :invalid_measure}

  @spec record(Exqlite.Sqlite3.db(), String.t(), pos_integer(), map()) :: :ok | {:error, term()}
  def record(conn, issue_id, seq, measurement) do
    execute(
      conn,
      """
      INSERT INTO measurements (issue_id, seq, measure, value, unit, dims, source, recorded_at)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?)
      """,
      [
        issue_id,
        seq,
        measurement.measure,
        measurement.value,
        measurement.unit,
        encode_dims(measurement.dims),
        measurement.source,
        now_iso()
      ]
    )
  end

  defp fetch(attrs, key, default \\ nil) do
    Map.get(attrs, key, Map.get(attrs, Atom.to_string(key), default))
  end

  defp validate_dims(dims) do
    if Enum.all?(dims, fn
         {key, value} when is_binary(key) and is_binary(value) ->
           Regex.match?(~r/^[a-z][a-z0-9_]*$/, key)

         _ ->
           false
       end) do
      :ok
    else
      {:error, :invalid_dimension_key}
    end
  end

  defp validate_kind(%{"kind" => kind}) when kind in ["estimate", "actual"], do: :ok
  defp validate_kind(_dims), do: {:error, :invalid_measurement_kind}

  defp validate_domain(value, "non_negative") when value >= 0, do: :ok
  defp validate_domain(_value, "non_negative"), do: {:error, :invalid_measure_value}
  defp validate_domain(_value, "any"), do: :ok

  defp encode_dims(dims) do
    dims
    |> Enum.sort_by(fn {key, _value} -> key end)
    |> Enum.map_join(",", fn {key, value} -> "#{Jason.encode!(key)}:#{Jason.encode!(value)}" end)
    |> then(&"{#{&1}}")
  end

  defp registered_measure(conn, name) do
    {:ok, stmt} =
      Exqlite.Sqlite3.prepare(conn, "SELECT unit, domain FROM measures WHERE name = ?")

    :ok = Exqlite.Sqlite3.bind(stmt, [name])

    try do
      case Exqlite.Sqlite3.step(conn, stmt) do
        {:row, [unit, domain]} -> %{unit: unit, domain: domain}
        :done -> nil
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

  defp now_iso, do: DateTime.utc_now() |> DateTime.to_iso8601()
end
