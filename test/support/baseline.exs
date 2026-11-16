defmodule Bee.Test.Baseline do
  @moduledoc false
  # Compares a create observed now with the 0.3.0 baseline captured by
  # test/support/baseline_capture.exs into test/fixtures/v0_3_0_create_baseline.exs.
  #
  # The comparison, for every recorded map, recursively:
  #   1. key sets are equal at every level, so a new key (such as external_key) fails;
  #   2. every other value is equal under ==;
  #   3. only the enumerated timestamps are normalised to :ts first: the issue's
  #      created_at and updated_at (in the create reply, the get reply and the export
  #      line) and the issue.created event's timestamp. Each is asserted separately: a
  #      binary that parses as ISO 8601, created_at <= updated_at, and the event time
  #      not before created_at;
  #   4. export lines are compared decoded, under the same rules, and their raw bytes
  #      are compared with only those timestamp values substituted.

  import ExUnit.Assertions

  @fixture Path.expand("../fixtures/v0_3_0_create_baseline.exs", __DIR__)

  def load do
    {term, _binding} = Code.eval_file(@fixture)
    term
  end

  def scenarios, do: load().scenarios

  def scenario(name), do: Keyword.fetch!(scenarios(), name)

  @doc "Runs a scenario's setup creates and its create on `server`, then observes it."
  def run(scenario, server, db_path, extra_opts \\ []) do
    Enum.each(scenario.inputs.setup, fn {title, opts} ->
      {:ok, _} = Bee.create(title, opts, server)
    end)

    reply = Bee.create(scenario.inputs.title, scenario.inputs.opts ++ extra_opts, server)
    {:ok, %{id: id}} = reply
    observe(reply, server, db_path, id)
  end

  @doc "Observes issue `id` in the shape the baseline records."
  def observe(reply, server, db_path, id) do
    prefix = GenServer.call(server, :prefix)
    raw_id = "#{prefix}-#{id}"
    get = Bee.get(id, server)

    with_conn(db_path, fn conn ->
      export_path =
        Path.join(System.tmp_dir!(), "bee_baseline_#{System.unique_integer([:positive])}.jsonl")

      try do
        :ok = Bee.Export.export(conn, export_path)

        export_lines =
          export_path
          |> File.read!()
          |> String.split("\n", trim: true)
          |> Enum.filter(&(Jason.decode!(&1)["id"] == raw_id))

        %{
          create: reply,
          get: get,
          labels:
            rows(conn, "SELECT issue_id, label FROM issue_labels WHERE issue_id = ?", [raw_id]),
          events: events(conn, raw_id),
          export: Enum.map(export_lines, &Jason.decode!/1),
          export_raw: export_lines,
          stored_external_key:
            rows(conn, "SELECT external_key FROM issues WHERE id = ?", [raw_id])
        }
      after
        File.rm(export_path)
        File.rm(export_path <> ".tmp")
      end
    end)
  end

  @doc """
  Asserts `actual` (from `observe/4`) matches `baseline` (a fixture scenario). The
  baseline's prefix must equal the server's, since ids are compared verbatim.
  `except:` leaves named sections out of the equality check; timestamps and the raw
  export are always checked.
  """
  def assert_matches_baseline(actual, baseline, opts \\ []) do
    sections = [:create, :get, :labels, :events, :export] -- Keyword.get(opts, :except, [])

    for section <- sections do
      assert_same(
        normalize(section, Map.fetch!(actual, section)),
        normalize(section, Map.fetch!(baseline, section)),
        [section]
      )
    end

    assert_raw_export(actual, baseline)
    assert_timestamps(actual)
    :ok
  end

  # --- normalisation of the enumerated timestamps ---

  defp normalize(section, {:ok, issue}) when section in [:create, :get],
    do: {:ok, issue |> put_ts(:created_at) |> put_ts(:updated_at)}

  defp normalize(:events, events), do: Enum.map(events, &put_ts(&1, :created_at))

  defp normalize(:export, lines),
    do: Enum.map(lines, &(&1 |> put_ts("created_at") |> put_ts("updated_at")))

  defp normalize(_section, value), do: value

  defp put_ts(map, key) do
    assert Map.has_key?(map, key), "missing timestamp #{inspect(key)} in #{inspect(map)}"
    Map.put(map, key, :ts)
  end

  defp assert_timestamps(actual) do
    {:ok, created} = actual.create
    {:ok, got} = actual.get
    [event] = actual.events

    for issue <- [created, got] do
      assert_issue_times(issue.created_at, issue.updated_at)
    end

    for line <- actual.export do
      assert_issue_times(line["created_at"], line["updated_at"])
    end

    assert DateTime.compare(parse!(event.created_at), parse!(created.created_at)) in [:eq, :gt],
           "event time #{event.created_at} is before created_at #{created.created_at}"
  end

  defp assert_issue_times(created_at, updated_at) do
    assert DateTime.compare(parse!(created_at), parse!(updated_at)) in [:lt, :eq],
           "created_at #{created_at} is after updated_at #{updated_at}"
  end

  defp parse!(value) do
    assert is_binary(value), "timestamp #{inspect(value)} is not a binary"
    assert {:ok, datetime, _offset} = DateTime.from_iso8601(value)
    datetime
  end

  defp assert_raw_export(actual, baseline) do
    assert length(actual.export_raw) == length(baseline.export_raw)

    [actual.export_raw, actual.export, baseline.export_raw, baseline.export]
    |> Enum.zip()
    |> Enum.each(fn {a_raw, a, b_raw, b} ->
      assert strip_ts(a_raw, a) == strip_ts(b_raw, b)
    end)
  end

  defp strip_ts(raw, decoded) do
    Enum.reduce(["created_at", "updated_at"], raw, fn key, acc ->
      String.replace(
        acc,
        Jason.encode!(%{key => decoded[key]}) |> trim_braces(),
        "\"#{key}\":\"ts\""
      )
    end)
  end

  defp trim_braces("{" <> rest), do: String.trim_trailing(rest, "}")

  # --- structural equality with key sets at every level ---

  defp assert_same(actual, expected, path) when is_map(actual) and is_map(expected) do
    actual_keys = actual |> Map.keys() |> MapSet.new()
    expected_keys = expected |> Map.keys() |> MapSet.new()

    assert actual_keys == expected_keys,
           "key sets differ at #{inspect(path)}: " <>
             "extra #{inspect(MapSet.difference(actual_keys, expected_keys) |> Enum.to_list())}, " <>
             "missing #{inspect(MapSet.difference(expected_keys, actual_keys) |> Enum.to_list())}"

    Enum.each(expected, fn {key, value} ->
      assert_same(Map.fetch!(actual, key), value, path ++ [key])
    end)
  end

  defp assert_same(actual, expected, path) when is_list(actual) and is_list(expected) do
    assert length(actual) == length(expected),
           "list lengths differ at #{inspect(path)}: #{inspect(actual)} vs #{inspect(expected)}"

    actual
    |> Enum.zip(expected)
    |> Enum.with_index()
    |> Enum.each(fn {{a, e}, i} -> assert_same(a, e, path ++ [i]) end)
  end

  defp assert_same(actual, expected, path) when is_tuple(actual) and is_tuple(expected) do
    assert_same(Tuple.to_list(actual), Tuple.to_list(expected), path)
  end

  defp assert_same(actual, expected, path) do
    assert actual == expected,
           "value differs at #{inspect(path)}: #{inspect(actual)} vs #{inspect(expected)}"
  end

  # --- SQLite helpers on a separate connection ---

  def with_conn(db_path, fun) do
    {:ok, conn} = Exqlite.Sqlite3.open(db_path)

    try do
      fun.(conn)
    after
      Exqlite.Sqlite3.close(conn)
    end
  end

  def events(conn, raw_id) do
    conn
    |> rows(
      "SELECT event_type, actor, payload, created_at FROM events " <>
        "WHERE issue_id = ? AND event_type = 'issue.created' ORDER BY id",
      [raw_id]
    )
    |> Enum.map(fn [type, actor, payload, created_at] ->
      %{
        type: type,
        actor: actor,
        fields: Jason.decode!(payload)["fields"],
        created_at: created_at
      }
    end)
  end

  def rows(conn, sql, params \\ []) do
    {:ok, stmt} = Exqlite.Sqlite3.prepare(conn, sql)
    :ok = Exqlite.Sqlite3.bind(stmt, params)

    try do
      Stream.repeatedly(fn -> Exqlite.Sqlite3.step(conn, stmt) end)
      |> Enum.take_while(&match?({:row, _}, &1))
      |> Enum.map(fn {:row, row} -> row end)
      |> Enum.sort()
    after
      Exqlite.Sqlite3.release(conn, stmt)
    end
  end
end
