defmodule Bee.Query.Withheld do
  @moduledoc false

  alias Bee.Query.Spec

  @relations [:comments]

  @spec build(Spec.t(), [map()], map(), String.t() | nil) :: {map(), keyword()}
  def build(%Spec{} = spec, issues, counts, next) do
    {withheld, refine} = relation_omissions(spec)
    {detail_withheld, detail_refine} = detail_omissions(spec)
    {limit_withheld, limit_refine} = limit_truncation(spec, issues, counts, next)

    {withheld |> Map.merge(detail_withheld) |> Map.merge(limit_withheld),
     refine ++ detail_refine ++ limit_refine}
  end

  defp detail_omissions(%Spec{detail: :minimal}) do
    {%{detail_omitted: [:blocks, :lock]}, [detail: :compact]}
  end

  defp detail_omissions(_spec), do: {%{}, []}

  defp relation_omissions(spec) do
    omitted = @relations -- spec.include

    if omitted == [] do
      {%{}, []}
    else
      {%{relation_omitted: omitted}, [include: @relations]}
    end
  end

  defp limit_truncation(%Spec{limit: nil}, _issues, _counts, _next), do: {%{}, []}

  # Keyset page: what is withheld is what lies after this page, counted from the
  # cursor in the same scan as the total; the refinement is the next cursor.
  defp limit_truncation(%Spec{after: cursor}, issues, %{remaining: remaining}, next)
       when is_binary(cursor) do
    omitted = max(remaining - length(issues), 0)

    if omitted > 0 and next,
      do: {%{limit: omitted}, [after: next]},
      else: {%{}, []}
  end

  defp limit_truncation(spec, issues, %{total: total}, _next) do
    offset = spec.offset || 0
    omitted = max(total - offset - length(issues), 0)

    if omitted > 0,
      do: {%{limit: omitted}, [offset: offset + length(issues)]},
      else: {%{}, []}
  end
end
