defmodule Bee.Query.Projection do
  @moduledoc false

  @presets %{
    minimal: [:id, :title, :status, :priority],
    compact: [
      :id,
      :title,
      :status,
      :priority,
      :issue_type,
      :project_id,
      :assigned_to,
      :parent,
      :created_at,
      :updated_at
    ],
    standard: [
      :id,
      :title,
      :status,
      :priority,
      :issue_type,
      :project_id,
      :assigned_to,
      :parent,
      :created_at,
      :updated_at,
      :description,
      :closed_at,
      :close_reason,
      :metadata
    ],
    full: [
      :id,
      :title,
      :status,
      :priority,
      :issue_type,
      :project_id,
      :assigned_to,
      :parent,
      :created_at,
      :updated_at,
      :description,
      :closed_at,
      :close_reason,
      :metadata
    ]
  }

  @spec project([map()], Bee.Query.Spec.t()) :: [map()]
  def project(issues, spec), do: Enum.map(issues, &project_issue(&1, spec))

  defp project_issue(issue, spec) do
    fields = Map.fetch!(@presets, spec.detail)

    issue
    |> Map.take(fields)
    |> Map.merge(relations(issue, spec))
  end

  defp relations(issue, spec) do
    %{labels: issue.labels, blocked_by: issue.blocked_by}
    |> maybe_put_comments(issue, spec)
    |> maybe_put_coordination_relations(issue, spec)
  end

  defp maybe_put_comments(relations, issue, spec) do
    if :comments in spec.include,
      do: Map.put(relations, :comments, issue.comments),
      else: relations
  end

  defp maybe_put_coordination_relations(relations, _issue, %{detail: :minimal}), do: relations

  defp maybe_put_coordination_relations(relations, issue, _spec) do
    relations
    |> Map.put(:blocks, issue.blocks)
    |> Map.put(:lock, issue.lock)
  end
end
