defmodule Bee.Query.Interpreter do
  @moduledoc false

  alias Bee.Query.Spec

  @type result :: %{issues: [map()], withheld: map(), refine: keyword()}

  @spec execute(Exqlite.Sqlite3.db(), Spec.t()) :: {:ok, result()} | {:error, term()}
  def execute(conn, %Spec{} = spec) do
    with {:ok, issues} <- Bee.Store.list_issues(conn, Spec.to_opts(spec)) do
      {withheld, refine} = Bee.Query.Withheld.build(conn, spec, issues)
      {:ok, %{issues: issues, withheld: withheld, refine: refine}}
    end
  end
end
