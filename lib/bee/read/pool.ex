defmodule Bee.Read.Pool do
  @moduledoc false
  use Supervisor

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

  @impl true
  def init(opts) do
    db_path = Keyword.fetch!(opts, :db_path)
    pool_name = Keyword.get(opts, :name, __MODULE__)

    fast_size = min(System.schedulers_online(), 8)
    compute_size = 2

    children = [
      {NimblePool,
       worker: {Bee.Read.Connection, db_path},
       pool_size: fast_size,
       name: fast_pool_name(pool_name)}
      |> Supervisor.child_spec(id: :fast_pool),
      {NimblePool,
       worker: {Bee.Read.Connection, db_path},
       pool_size: compute_size,
       name: compute_pool_name(pool_name)}
      |> Supervisor.child_spec(id: :compute_pool)
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  @doc """
  Checks out a read-only connection from the appropriate lane.

  `fun` receives the connection and must return `{:ok, result}` or `{:error, reason}`.
  The connection is automatically returned to the pool after `fun` returns.
  """
  @spec with_connection(atom(), (Exqlite.Sqlite3.db() -> {:ok, term()} | {:error, term()})) ::
          {:ok, term()} | {:error, term()}
  def with_connection(lane, fun) when lane in [:fast, :compute] do
    pool = pool_name(lane)

    NimblePool.checkout!(
      pool,
      nil,
      fn _from, conn ->
        try do
          {fun.(conn), conn}
        rescue
          e -> {{:error, {:read_failed, e}}, conn}
        end
      end,
      :infinity
    )
  end

  def fast_pool_name(base), do: :"#{base}.Fast"
  def compute_pool_name(base), do: :"#{base}.Compute"

  defp pool_name(:fast), do: fast_pool_name(__MODULE__)
  defp pool_name(:compute), do: compute_pool_name(__MODULE__)
end
