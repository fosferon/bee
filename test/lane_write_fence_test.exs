defmodule Bee.LaneWriteFenceTest do
  use ExUnit.Case, async: false

  setup do
    root =
      Path.join(System.tmp_dir!(), "bee-fence-" <> Base.encode16(:crypto.strong_rand_bytes(8)))

    File.mkdir_p!(root)

    repo =
      start_supervised!(
        {Bee.Repo,
         db_path: Path.join(root, "bee.db"),
         prefix: "GC",
         jsonl_path: nil,
         name: __MODULE__,
         lane_write_fence: true}
      )

    on_exit(fn -> File.rm_rf!(root) end)
    %{server: repo, root: root}
  end

  defp link(repo, issue, key \\ "association") do
    Bee.associate_lane_issue(
      %{
        command_id: key,
        lane_id: "lane_0123456789abcdef01234567",
        issue_id: "GC-#{issue.id}",
        role: "member",
        project_id: issue.project_id
      },
      repo
    )
  end

  test "neutral writers retain their legacy results and positive classification", %{server: repo} do
    assert {:ok, :enabled} = Bee.lane_write_fence_status(repo)
    assert {:ok, first} = Bee.create("Neutral", [], repo)
    assert {:ok, other} = Bee.create("Other", [], repo)

    assert {:ok,
            %{
              classification: :legacy_only_excluded_from_lane_truth,
              bindings: [],
              targets: targets
            }} = Bee.classify_lane_write({:block, first.id, other.id}, repo)

    assert Enum.sort(targets) == ["GC-1", "GC-2"]
    assert :ok = Bee.comment(first.id, "retained", [], repo)
    assert :ok = Bee.update(first.id, %{title: "Changed"}, repo)
    assert :ok = Bee.block(first.id, other.id, repo)
    assert {:ok, %{title: "Changed"}} = Bee.get(first.id, repo)
  end

  test "binding needs no request lane field to deny legacy writes", %{server: repo} do
    assert {:ok, issue} = Bee.create("Protected", [], repo)
    assert {:ok, _} = link(repo, issue)
    assert {:ok, before} = Bee.get(issue.id, repo)

    for request <- [
          {:update, issue.id, %{title: "forged"}},
          {:comment, issue.id, "forged", []},
          {:unlock, issue.id},
          {:assign, issue.id, "worker"},
          {:measure, issue.id, %{measure: "cost", value: 1}}
        ] do
      assert {:error, :lane_bound_owner_command_required} = GenServer.call(repo, request)
    end

    assert {:ok, ^before} = Bee.get(issue.id, repo)
    assert {:ok, []} = Bee.get_comments(issue.id, repo)
    assert {:error, :owner_connection_private} = GenServer.call(repo, :conn)
  end

  test "graph mutations qualify both endpoint targets before any change", %{server: repo} do
    assert {:ok, neutral} = Bee.create("Neutral", [], repo)
    assert {:ok, linked} = Bee.create("Linked", [], repo)
    assert {:ok, _} = link(repo, linked)

    for op <- [:block, :unblock] do
      assert {:error, :lane_bound_owner_command_required} =
               GenServer.call(repo, {op, neutral.id, linked.id})
    end

    assert {:ok, %{blocks: [], blocked_by: []}} = Bee.get(neutral.id, repo)
  end

  test "create and parent changes qualify both old and new relationships", %{server: repo} do
    assert {:ok, parent} = Bee.create("Parent", [], repo)
    assert {:ok, child} = Bee.create("Child", [parent: parent.id], repo)
    assert {:ok, other} = Bee.create("Other", [], repo)
    assert {:ok, _} = link(repo, parent)

    assert {:error, :lane_bound_owner_command_required} =
             Bee.create("Forbidden", [parent: parent.id], repo)

    assert {:error, :lane_bound_owner_command_required} =
             Bee.update(child.id, %{parent: other.id}, repo)

    assert {:error, :lane_bound_owner_command_required} =
             Bee.update(other.id, %{parent: parent.id}, repo)

    assert {:ok, %{parent: id}} = Bee.get(child.id, repo)
    assert id == parent.id
    assert {:ok, next} = Bee.create("Still neutral", [], repo)
    assert next.id == other.id + 1
  end

  test "imports classify every issue and graph endpoint before writing", %{
    server: repo,
    root: root
  } do
    assert {:ok, neutral} = Bee.create("First unchanged", [], repo)
    assert {:ok, linked} = Bee.create("Linked unchanged", [], repo)
    assert {:ok, _} = link(repo, linked)
    path = Path.join(root, "import.jsonl")

    File.write!(
      path,
      Jason.encode!(%{id: "GC-#{neutral.id}", title: "changed"}) <>
        "\n" <> Jason.encode!(%{id: "GC-#{linked.id}", title: "changed"})
    )

    assert {:error, :lane_bound_owner_command_required} = Bee.import_jsonl(path, repo)
    assert {:ok, %{title: "First unchanged"}} = Bee.get(neutral.id, repo)

    File.write!(
      path,
      Jason.encode!(%{
        id: "GC-#{neutral.id}",
        title: "changed",
        dependencies: [%{depends_on_id: "GC-#{linked.id}"}]
      })
    )

    assert {:error, :lane_bound_owner_command_required} = Bee.import_jsonl(path, repo)
    assert {:ok, %{title: "First unchanged"}} = Bee.get(neutral.id, repo)
  end

  test "a later neutral import failure rolls back the entire snapshot", %{
    server: repo,
    root: root
  } do
    assert {:ok, neutral} = Bee.create("Unchanged", [], repo)
    path = Path.join(root, "import.jsonl")

    File.write!(
      path,
      Jason.encode!(%{id: "GC-#{neutral.id}", title: "changed"}) <>
        "\n" <>
        Jason.encode!(%{
          id: "GC-999",
          title: "valid title",
          dependencies: [%{depends_on_id: "GC-1000"}]
        })
    )

    assert {:error, _} = Bee.import_jsonl(path, repo)
    assert {:ok, %{title: "Unchanged"}} = Bee.get(neutral.id, repo)
    assert {:error, :not_found} = Bee.get(999, repo)
    assert Process.alive?(repo)
  end

  test "owner restart retains linked classification", %{server: repo, root: root} do
    assert {:ok, linked} = Bee.create("Linked", [], repo)
    assert {:ok, _} = link(repo, linked)
    stop_supervised!(Bee.Repo)

    restarted =
      start_supervised!(
        {Bee.Repo,
         db_path: Path.join(root, "bee.db"),
         prefix: "GC",
         jsonl_path: nil,
         name: __MODULE__,
         lane_write_fence: true}
      )

    assert {:error, :lane_bound_owner_command_required} =
             Bee.comment(linked.id, "late writeback", [], restarted)
  end

  test "unknown mutations and unreadable binding tables deny without owner loss", %{server: repo} do
    assert {:error, :unclassified_bee_mutation} = GenServer.call(repo, {:future_write, 1})
    # Fault injection against the disposable fixture; production never borrows this connection.
    conn = :sys.get_state(repo).conn
    assert :ok = Exqlite.Sqlite3.execute(conn, "DROP TABLE lane_issue_links")
    assert {:error, _} = Bee.comment(1, "must deny", [], repo)
    assert Process.alive?(repo)
  end

  test "invalid targets deny without killing the owner", %{server: repo} do
    for request <- [
          {:update, nil, %{}},
          {:comment, nil, "x", []},
          {:block, 1, nil},
          {:lock, nil, []}
        ] do
      assert {:error, :invalid_lane_mutation} = GenServer.call(repo, request)
    end

    assert Process.alive?(repo)
  end

  test "the classification inventory covers every legacy owner message" do
    {:ok, quoted} = "lib/bee/repo.ex" |> File.read!() |> Code.string_to_quoted()

    {_, operations} =
      Macro.prewalk(quoted, MapSet.new(), fn
        {:defp, _, [head | _]} = node, acc ->
          call =
            case head do
              {:when, _, [call | _]} -> call
              other -> other
            end

          case call do
            {:handle_request, _, [request | _]} ->
              request =
                case request do
                  {:=, _, [pattern, _]} -> pattern
                  pattern -> pattern
                end

              op =
                case request do
                  {:{}, _, [op | _]} -> op
                  {op, _args} -> op
                  other -> other
                end

              {node, MapSet.put(acc, op)}

            _ ->
              {node, acc}
          end

        node, acc ->
          {node, acc}
      end)

    allowed =
      MapSet.new(
        Bee.Store.LaneWriteFence.reads() ++
          Bee.Store.LaneWriteFence.mutations() ++
          [:conn, :associate_lane_issue, :import_entries, :sweep_expired_targets]
      )

    assert MapSet.subset?(operations, allowed)
    assert {:module, Bee.Store.LaneWriteFence} = Code.ensure_loaded(Bee.Store.LaneWriteFence)
  end

  test "import qualifies old linked parent", %{server: repo, root: root} do
    assert {:ok, parent} = Bee.create("Parent", [], repo)
    assert {:ok, child} = Bee.create("Child", [parent: parent.id], repo)
    assert {:ok, _} = link(repo, parent)
    path = Path.join(root, "old-parent.jsonl")
    File.write!(path, Jason.encode!(%{id: "GC-#{child.id}", title: "changed"}))
    assert {:error, :lane_bound_owner_command_required} = Bee.import_jsonl(path, repo)
    assert {:ok, %{parent: retained}} = Bee.get(child.id, repo)
    assert retained == parent.id
  end

  test "import qualifies existing linked edge endpoints", %{server: repo, root: root} do
    assert {:ok, neutral} = Bee.create("Neutral", [], repo)
    assert {:ok, linked} = Bee.create("Linked", [], repo)
    assert :ok = Bee.block(neutral.id, linked.id, repo)
    assert {:ok, _} = link(repo, linked)
    path = Path.join(root, "old-edge.jsonl")
    File.write!(path, Jason.encode!(%{id: "GC-#{neutral.id}", title: "changed"}))
    assert {:error, :lane_bound_owner_command_required} = Bee.import_jsonl(path, repo)
    assert {:ok, %{blocks: blocks}} = Bee.get(linked.id, repo)
    assert blocks == [neutral.id]
  end

  test "failed later issue upsert rolls back complete import", %{server: repo, root: root} do
    assert {:ok, first} = Bee.create("First unchanged", [], repo)
    assert {:ok, second} = Bee.create("Second unchanged", [], repo)
    assert :ok = Bee.comment(second.id, "Existing history", [], repo)
    conn = :sys.get_state(repo).conn

    assert :ok =
             Exqlite.Sqlite3.execute(
               conn,
               "CREATE TRIGGER deny_second_import BEFORE INSERT ON issues WHEN NEW.id = 'GC-#{second.id}' BEGIN SELECT RAISE(ABORT, 'fixture failure'); END"
             )

    path = Path.join(root, "failed-upsert.jsonl")

    File.write!(
      path,
      Jason.encode!(%{id: "GC-#{first.id}", title: "First changed"}) <>
        "\n" <> Jason.encode!(%{id: "GC-#{second.id}", title: "Second changed"})
    )

    result = Bee.import_jsonl(path, repo)
    assert match?({:error, _}, result)
    assert {:ok, %{title: "First unchanged"}} = Bee.get(first.id, repo)
    assert {:ok, [_]} = Bee.get_comments(second.id, repo)
  end

  test "prepared sweeper messages are private in default mode", %{root: root} do
    default_repo =
      start_supervised!(
        {Bee.Repo,
         db_path: Path.join(root, "default.db"),
         prefix: "GC",
         jsonl_path: nil,
         name: Bee.DefaultAcceptanceProbe},
        id: :default_repo
      )

    assert {:ok, :disabled} = Bee.lane_write_fence_status(default_repo)
    assert {:ok, issue} = Bee.create("Neutral", [], default_repo)
    assert {:ok, _} = Bee.lock(issue.id, [ttl: 60], default_repo)
    result = GenServer.call(default_repo, {:sweep_expired_targets, ["GC-#{issue.id}"]})
    assert match?({:error, _}, result)
  end

  test "default imports roll back failures and leave subsequent creation usable", %{root: root} do
    repo =
      start_supervised!(
        {Bee.Repo,
         db_path: Path.join(root, "default-atomic.db"),
         prefix: "GC",
         jsonl_path: nil,
         name: Bee.DefaultAtomicProbe},
        id: :default_atomic
      )

    path = Path.join(root, "default-import.jsonl")

    File.write!(
      path,
      Jason.encode!(%{id: "GC-1", title: "First"}) <>
        "\n" <>
        Jason.encode!(%{
          id: "GC-2",
          title: "Second",
          dependencies: [%{depends_on_id: "GC-1", type: "unknown-type"}]
        })
    )

    assert {:error, _} = Bee.import_jsonl(path, repo)
    assert {:error, :not_found} = Bee.get(1, repo)
    assert {:error, :not_found} = Bee.get(2, repo)
    assert {:ok, %{id: 1}} = Bee.create("Usable after rollback", [], repo)
    assert {:error, :private_owner_message} = GenServer.call(repo, {:import_entries, []})
  end

  test "successful import changes the row while retaining its owner event history", %{
    server: repo,
    root: root
  } do
    assert {:ok, issue} = Bee.create("Original", [], repo)
    conn = :sys.get_state(repo).conn
    {:ok, stmt} = Exqlite.Sqlite3.prepare(conn, "SELECT COUNT(*) FROM events WHERE issue_id = ?")
    :ok = Exqlite.Sqlite3.bind(stmt, ["GC-#{issue.id}"])
    assert {:row, [count]} = Exqlite.Sqlite3.step(conn, stmt)
    Exqlite.Sqlite3.release(conn, stmt)
    path = Path.join(root, "success-import.jsonl")
    File.write!(path, Jason.encode!(%{id: "GC-#{issue.id}", title: "Imported"}))
    assert {:ok, 1} = Bee.import_jsonl(path, repo)
    assert {:ok, %{title: "Imported"}} = Bee.get(issue.id, repo)
    {:ok, stmt} = Exqlite.Sqlite3.prepare(conn, "SELECT COUNT(*) FROM events WHERE issue_id = ?")
    :ok = Exqlite.Sqlite3.bind(stmt, ["GC-#{issue.id}"])
    assert {:row, [^count]} = Exqlite.Sqlite3.step(conn, stmt)
    Exqlite.Sqlite3.release(conn, stmt)
  end
end
