defmodule Bee.TreeQueryPerfTest do
  # GC-5834 performance budget, on a fixture the size and shape of the live Bee
  # (5,300 issues, about half with a parent, trees up to 5 deep, gating edges):
  # a board lane page (limit 50, fold + path) under 150 ms and its total under
  # 50 ms. Excluded by default; run with `mix test --only perf`.
  use ExUnit.Case

  @moduletag :perf
  @moduletag timeout: 600_000

  @issues 5_300
  @runs 20

  setup_all do
    db_path = Path.join(System.tmp_dir!(), "bee_perf_#{:erlang.unique_integer([:positive])}.db")
    name = :"bee_perf_#{:erlang.unique_integer([:positive])}"

    {:ok, pid} =
      Bee.Repo.start_link(db_path: db_path, prefix: "perf", jsonl_path: nil, name: name)

    seed(GenServer.call(name, :conn))

    on_exit(fn ->
      if Process.alive?(pid), do: GenServer.stop(pid)
      File.rm(db_path)
    end)

    %{server: name}
  end

  # Deterministic shape: every 7th issue is a root epic-ish parent; about 53% of
  # issues get a parent chosen among earlier issues less than 5 levels deep;
  # statuses cycle open/open/closed/in_progress/open/closed/cancelled; every 11th
  # open issue is gated by an earlier one.
  defp seed(conn) do
    :rand.seed(:exsss, {5834, 5834, 5834})
    :ok = Exqlite.Sqlite3.execute(conn, "BEGIN")
    statuses = ~w(open open closed in_progress open closed cancelled)

    {:ok, issue} =
      Exqlite.Sqlite3.prepare(conn, """
      INSERT INTO issues (id, title, status, priority, issue_type, parent, created_at, updated_at)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?)
      """)

    {:ok, label} = Exqlite.Sqlite3.prepare(conn, "INSERT INTO issue_labels VALUES (?, ?)")

    {:ok, dep} =
      Exqlite.Sqlite3.prepare(
        conn,
        "INSERT INTO dependencies (issue_id, depends_on_id, dep_type, created_at) VALUES (?, ?, 'blocks', ?)"
      )

    Enum.reduce(1..@issues, %{}, fn n, depths ->
      id = "perf-#{n}"

      parent =
        if n > 1 and :rand.uniform(100) <= 53 do
          candidate = "perf-#{:rand.uniform(n - 1)}"
          if Map.fetch!(depths, candidate) < 4, do: candidate
        end

      depth = if parent, do: Map.fetch!(depths, parent) + 1, else: 0
      status = Enum.at(statuses, rem(n, length(statuses)))
      priority = if rem(n, 5) == 0, do: nil, else: :rand.uniform(10)

      stamp =
        "2026-01-01T00:00:#{String.pad_leading(Integer.to_string(rem(n, 60)), 2, "0")}.#{n}Z"

      :ok =
        Exqlite.Sqlite3.bind(issue, [
          id,
          "Issue #{n}",
          status,
          priority,
          "task",
          parent,
          stamp,
          stamp
        ])

      :done = Exqlite.Sqlite3.step(conn, issue)
      :ok = Exqlite.Sqlite3.reset(issue)

      :ok = Exqlite.Sqlite3.bind(label, [id, Enum.at(~w(ui api infra docs), rem(n, 4))])
      :done = Exqlite.Sqlite3.step(conn, label)
      :ok = Exqlite.Sqlite3.reset(label)

      if rem(n, 11) == 0 do
        :ok = Exqlite.Sqlite3.bind(dep, [id, "perf-#{:rand.uniform(n - 1)}", stamp])
        :done = Exqlite.Sqlite3.step(conn, dep)
        :ok = Exqlite.Sqlite3.reset(dep)
      end

      Map.put(depths, id, depth)
    end)

    :ok = Exqlite.Sqlite3.execute(conn, "COMMIT")
    Enum.each([issue, label, dep], &Exqlite.Sqlite3.release(conn, &1))
  end

  defp median_ms(fun) do
    _warm = fun.()

    1..@runs
    |> Enum.map(fn _ ->
      {micros, _} = :timer.tc(fun)
      micros / 1000
    end)
    |> Enum.sort()
    |> Enum.at(div(@runs, 2))
  end

  test "a lane page with fold + path and its total stay within budget", %{server: s} do
    lanes = [
      ready: [status: "open", ready: true],
      in_progress: [status: "in_progress"],
      blocked: [status: "open", blocked: true]
    ]

    for {lane, filters} <- lanes do
      spec =
        filters ++ [order_by: [priority: :desc], limit: 50, depth: 10, fold: true, path: true]

      {:ok, first} = Bee.query(spec, s)
      assert length(first.issues) == 50 or is_nil(first.next)

      page_ms = median_ms(fn -> {:ok, _} = Bee.query(spec, s) end)

      next_ms =
        if first.next,
          do: median_ms(fn -> {:ok, _} = Bee.query(spec ++ [after: first.next], s) end)

      total_ms = median_ms(fn -> {:ok, _} = Bee.count(filters ++ [depth: 10], s) end)

      IO.puts(
        "[perf] #{lane}: total=#{first.total} page=#{Float.round(page_ms, 1)}ms " <>
          "next_page=#{next_ms && Float.round(next_ms, 1)}ms count=#{Float.round(total_ms, 1)}ms"
      )

      assert page_ms < 150, "#{lane} page took #{page_ms}ms (budget 150ms)"
      assert total_ms < 50, "#{lane} total took #{total_ms}ms (budget 50ms)"
    end
  end
end
