defmodule Bee.RegistryWritesTest do
  use ExUnit.Case, async: false

  setup do
    root = Path.join(System.tmp_dir!(), "bee-registry-#{System.unique_integer([:positive])}")
    File.mkdir_p!(root)
    db = Path.join(root, "bee.db")

    repo =
      start_supervised!(
        {Bee.Repo,
         db_path: db, prefix: "GC", jsonl_path: nil, name: __MODULE__, lane_write_fence: true}
      )

    on_exit(fn -> File.rm_rf!(root) end)
    %{repo: repo, db: db}
  end

  defp entry(id, name \\ "Registry") do
    %{
      id: id,
      name: name,
      path: nil,
      status: "active",
      description: nil,
      stack: nil,
      domain: nil,
      repo_url: nil,
      canonical_path: nil,
      source: "test",
      last_synced_at: nil,
      metadata: "{}"
    }
  end

  defp link(repo, issue) do
    Bee.associate_lane_issue(
      %{
        command_id: "link",
        lane_id: "lane_0123456789abcdef01234567",
        issue_id: "GC-#{issue.id}",
        role: "member",
        project_id: issue.project_id
      },
      repo
    )
  end

  defp sql(db, sql) do
    {:ok, conn} = Exqlite.Sqlite3.open(db)

    try do
      :ok = Exqlite.Sqlite3.execute(conn, sql)
    after
      Exqlite.Sqlite3.close(conn)
    end
  end

  test "registry snapshot retains identity and refuses stale updates", %{repo: repo} do
    assert {:ok, first} = Bee.upsert_project_registry("p", entry("p"), nil, repo)
    assert {:ok, second} = Bee.upsert_project_registry("p", entry("p", "Updated"), first, repo)
    assert Enum.at(first, 4) == Enum.at(second, 4)
    assert Enum.at(second, 1) == "Updated"

    assert {:error, :project_version_conflict} =
             Bee.upsert_project_registry("p", entry("p", "Stale"), first, repo)

    assert {:error, :invalid_project_entry} =
             Bee.upsert_project_registry("p", %{id: "other"}, second, repo)

    assert {:error, :invalid_project_entry} =
             Bee.upsert_project_registry("p", fn _ -> :ok end, second, repo)

    assert Process.alive?(repo)
  end

  test "linked project denies the complete owner mutation", %{repo: repo} do
    assert {:ok, first} = Bee.upsert_project_registry("p", entry("p"), nil, repo)
    assert {:ok, issue} = Bee.create("Linked", [project_id: "p"], repo)
    assert {:ok, _} = link(repo, issue)

    assert {:error, :lane_bound_owner_command_required} =
             Bee.upsert_project_registry("p", entry("p", "Forbidden"), first, repo)
  end

  test "bulk fence denies every target before partial updates", %{repo: repo} do
    assert {:ok, _} = Bee.upsert_project_registry("p", entry("p"), nil, repo)
    assert {:ok, first} = Bee.create("First", [], repo)
    assert {:ok, linked} = Bee.create("Linked", [], repo)
    assert {:ok, _} = link(repo, linked)
    rows = Enum.map([first, linked], &%{id: "GC-#{&1.id}", project_id: "p", rule: "test"})

    assert {:error, :lane_bound_owner_command_required} =
             Bee.backfill_projects(rows, "run", DateTime.utc_now() |> DateTime.to_iso8601(), repo)

    assert {:ok, %{project_id: nil}} = Bee.get(first.id, repo)
  end

  test "bulk write and audit failure roll back the entire owner transaction", %{
    repo: repo,
    db: db
  } do
    assert {:ok, _} = Bee.upsert_project_registry("p", entry("p"), nil, repo)
    assert {:ok, first} = Bee.create("First", [], repo)
    assert {:ok, last} = Bee.create("Last", [], repo)

    sql(
      db,
      "CREATE TRIGGER fail_backfill BEFORE INSERT ON issue_project_backfill_log WHEN NEW.issue_id = 'GC-#{last.id}' BEGIN SELECT RAISE(ABORT, 'audit failed'); END;"
    )

    rows = Enum.map([first, last], &%{id: "GC-#{&1.id}", project_id: "p", rule: "test"})

    assert {:error, _} =
             Bee.backfill_projects(rows, "run", DateTime.utc_now() |> DateTime.to_iso8601(), repo)

    for issue <- [first, last], do: assert({:ok, %{project_id: nil}} = Bee.get(issue.id, repo))
    sql(db, "DROP TRIGGER fail_backfill")

    assert {:ok, 2} =
             Bee.backfill_projects(rows, "run", DateTime.utc_now() |> DateTime.to_iso8601(), repo)

    assert {:ok, %{updated_at: unchanged}} = Bee.get(first.id, repo)
    assert unchanged == first.updated_at

    assert {:ok, 0} =
             Bee.backfill_projects(
               rows,
               "again",
               DateTime.utc_now() |> DateTime.to_iso8601(),
               repo
             )
  end

  test "malformed bulk IDs return typed errors without killing either owner mode", ctx do
    unfenced =
      start_supervised!(
        {Bee.Repo,
         db_path: ctx.db <> ".unfenced",
         prefix: "GC",
         jsonl_path: nil,
         name: Bee.UnfencedRegistryProbe},
        id: :unfenced
      )

    for repo <- [ctx.repo, unfenced], id <- [nil, %{}, [], 42, ""] do
      assert {:error, _} = Bee.upsert_project_registry(id, %{}, nil, repo)
      assert Process.alive?(repo)
    end

    for repo <- [ctx.repo, unfenced], id <- ["", "bad", "GC-", "OTHER-1", -1, nil, %{}] do
      assert {:error, _} =
               Bee.backfill_projects(
                 [%{id: id, project_id: "p", rule: "probe"}],
                 "probe",
                 DateTime.utc_now() |> DateTime.to_iso8601(),
                 repo
               )

      assert Process.alive?(repo)
    end
  end

  test "racing initial project snapshots cannot overwrite the winner", %{repo: repo} do
    results =
      Enum.map(["First", "Second"], fn name ->
        Task.async(fn -> Bee.upsert_project_registry("p", entry("p", name), nil, repo) end)
      end)
      |> Enum.map(&Task.await/1)

    assert Enum.count(results, &match?({:ok, _}, &1)) == 1
    assert Enum.count(results, &(&1 == {:error, :project_version_conflict})) == 1
  end

  test "legacy issue update propagates column and label failures", %{repo: repo, db: db} do
    assert {:ok, issue} = Bee.create("Before", [labels: ["old"]], repo)

    sql(
      db,
      "CREATE TRIGGER fail_update BEFORE UPDATE ON issues BEGIN SELECT RAISE(ABORT, 'update failed'); END;"
    )

    assert {:error, _} = Bee.update(issue.id, %{status: "closed"}, repo)
    assert {:ok, %{status: "open"}} = Bee.get(issue.id, repo)

    sql(
      db,
      "DROP TRIGGER fail_update; CREATE TRIGGER fail_label BEFORE INSERT ON issue_labels BEGIN SELECT RAISE(ABORT, 'label failed'); END;"
    )

    assert {:error, _} = Bee.update(issue.id, %{title: "After", labels: ["new"]}, repo)
    assert {:ok, %{title: "Before", labels: ["old"]}} = Bee.get(issue.id, repo)
  end
end
