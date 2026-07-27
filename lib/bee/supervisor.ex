defmodule Bee.Supervisor do
  @moduledoc false
  use Supervisor

  @doc """
  Starts the Bee supervision tree with :rest_for_one semantics (AD-22).

  ## Boot sequence

  1. **Migrate** — runs pending migrations synchronously in init/1 before
     any children start. This prevents race conditions between the Migrate
     task and the Repo both accessing the DB.
  2. **Repo** (GenServer, traps exits) — writer + graph owner.
  3. **Read.Pool** (Supervisor) — two-lane NimblePool for read-only connections.
  4. **Sweeper** (GenServer) — lock-sweeper (Story 3.5; placeholder here).

  ## Shutdown invariant (AD-22, Story 3.3)

  Three exit paths, each with a different guarantee:

  | path           | when                          | terminate/2? | what runs                     |
  | -------------- | ----------------------------- | ------------ | ----------------------------- |
  | orderly        | supervisor asks to stop       | yes          | JSONL flush, WAL TRUNCATE     |
  | trapped crash  | exit signal caught            | yes          | JSONL flush, WAL TRUNCATE     |
  | brutal kill    | hard kill or timeout          | NO           | nothing; next boot recovers   |

  On orderly/trapped: Repo stops its pool (if owned), TRUNCATE checkpoint
  succeeds because no readers hold the WAL, then JSONL flush runs.

  On brutal kill: terminate/2 does NOT run. The WAL may contain uncommitted
  pages; the next boot's PASSIVE checkpoint timer (60s) recovers. The JSONL
  trail may miss the last event window; it is recoverable by re-export since
  JSONL is derived from the DB (AD-17).

  ## :rest_for_one semantics

  If Repo crashes    → restart Repo, Pool, Sweeper.
  If Pool crashes    → restart Pool, Sweeper.
  If Sweeper crashes → restart Sweeper only.

  (Migrate runs in init/1, not as a supervised child — it cannot crash
  independently. If it fails, the supervisor itself fails to start.)
  """
  def start_link(opts) do
    # Run migrations synchronously before starting the supervision tree.
    # This prevents race conditions between concurrent DB access.
    db_path = Keyword.fetch!(opts, :db_path)
    db_path |> Path.dirname() |> File.mkdir_p!()

    case Bee.Store.Migrate.run_at_boot(db_path) do
      :ok -> :ok
      {:error, reason} -> exit({:migration_failed, reason})
    end

    Supervisor.start_link(__MODULE__, opts, name: Keyword.get(opts, :name))
  end

  @impl true
  def init(opts) do
    db_path = Keyword.fetch!(opts, :db_path)
    prefix = Keyword.get(opts, :prefix, "bee")
    jsonl_path = Keyword.get(opts, :jsonl_path)
    repo_name = Keyword.get(opts, :repo_name, Bee.Repo)
    pool_name = Keyword.get(opts, :pool_name, :"#{repo_name}.ReadPool")
    sweeper_name = Keyword.get(opts, :sweeper_name, :"#{repo_name}.Sweeper")

    children = [
      # Child 1: Repo (GenServer, traps exits, :shutdown :infinity for flush bound)
      %{
        id: Bee.Repo,
        start:
          {Bee.Repo, :start_link,
           [
             [
               db_path: db_path,
               prefix: prefix,
               jsonl_path: jsonl_path,
               name: repo_name,
               start_pool?: false,
               skip_migration?: true,
               pool_name: pool_name
             ]
           ]},
        shutdown: :infinity,
        type: :worker
      },

      # Child 2: Read.Pool (Supervisor with two NimblePool children)
      %{
        id: Bee.Read.Pool,
        start: {Bee.Read.Pool, :start_link, [[db_path: db_path, name: pool_name]]},
        shutdown: :infinity,
        type: :supervisor
      },

      # Child 3: Sweeper (placeholder — Story 3.5 fills this in)
      %{
        id: Bee.Store.Locks.Sweeper,
        start: {Bee.Store.Locks.Sweeper, :start_link, [[name: sweeper_name, repo: repo_name]]},
        restart: :permanent,
        shutdown: 5_000,
        type: :worker
      }
    ]

    Supervisor.init(children, strategy: :rest_for_one, max_restarts: 3, max_seconds: 60)
  end
end
