defmodule Bee.Query.Projection do
  @moduledoc false

  @presets %{
    minimal: [:id, :title],
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

  @relations [:labels, :blocked_by, :blocks, :comments, :lock]

  @spec project([map()], Bee.Query.Spec.t()) :: [map()]
  def project(issues, spec), do: Enum.map(issues, &project_issue(&1, spec))

  defp project_issue(issue, spec) do
    fields = Map.fetch!(@presets, spec.detail)

    issue
    |> Map.take(fields)
    |> Map.merge(relations(issue, spec))
  end

  defp relations(issue, spec) do
    Map.new(@relations, fn
      :comments ->
        {:comments, if(:comments in spec.include, do: issue.comments, else: :not_loaded)}

      :labels ->
        {:labels, issue.labels}

      :blocked_by ->
        {:blocked_by, issue.blocked_by}

      relation when spec.detail == :minimal ->
        {relation, :not_loaded}

      relation ->
        {relation, Map.fetch!(issue, relation)}
    end)
  end
end
