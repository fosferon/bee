defmodule Bee.Query.Withheld do
  @moduledoc false

  alias Bee.Query.Spec

  @relations [:comments]

  @spec build(Exqlite.Sqlite3.db(), Spec.t(), [map()]) :: {map(), keyword()}
  def build(conn, %Spec{} = spec, issues) do
    {withheld, refine} = relation_omissions(spec)
    {limit_withheld, limit_refine} = limit_truncation(conn, spec, issues)

    {Map.merge(withheld, limit_withheld), refine ++ limit_refine}
  end

  defp relation_omissions(spec) do
    omitted = @relations -- spec.include

    if omitted == [] do
      {%{}, []}
    else
      {%{relation_omitted: omitted}, [include: @relations]}
    end
  end

  defp limit_truncation(_conn, %Spec{limit: nil}, _issues), do: {%{}, []}

  defp limit_truncation(conn, spec, issues) do
    {:ok, total} = Bee.Store.count_issues(conn, spec |> Spec.to_opts() |> Keyword.drop([:limit, :offset]))
    offset = spec.offset || 0
    omitted = max(total - offset - length(issues), 0)

    if omitted > 0, do: {%{limit: omitted}, [limit: nil]}, else: {%{}, []}
  end
end
