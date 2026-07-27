defmodule Bee.Query.Interpreter do
  @moduledoc false

  alias Bee.Query.Spec

  @type result :: %{issues: [map()], withheld: map(), refine: keyword()}

  @spec execute(Exqlite.Sqlite3.db(), Spec.t()) :: {:ok, result()} | {:error, term()}
  def execute(conn, %Spec{} = spec) do
    with {:ok, issues} <- Bee.Store.list_issues(conn, Spec.to_opts(spec)) do
      {withheld, refine} = Bee.Query.Withheld.build(conn, spec, issues)
      {issues, transformed} =
        issues
        |> Bee.Query.Projection.project(spec)
        |> Enum.map(&Bee.Query.Transform.apply(&1, spec.transforms))
        |> Enum.unzip()

      transformed = Enum.reject(transformed, &(&1 == %{}))
      withheld = if transformed == [], do: withheld, else: Map.put(withheld, :transformed, transformed)
      refine = if transformed == [], do: refine, else: refine ++ [transforms: %{}]

      {:ok, %{issues: issues, withheld: withheld, refine: refine}}
    end
  end
end
