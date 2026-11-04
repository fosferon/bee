defmodule Bee.Query.Spec do
  @moduledoc false

  @order_columns ~w(created_at updated_at priority id)a
  @order_directions [:asc, :desc]
  @include_relations [:comments, :labels]
  @details [:minimal, :compact, :standard, :full]
  @fields [
    :text,
    :status,
    :project_id,
    :project_ids,
    :ready,
    :assigned_to,
    :labels,
    :order_by,
    :limit,
    :offset,
    :include,
    :detail,
    :transforms,
    :under,
    :include_root,
    :depth,
    :fold,
    :path,
    :keep_ancestors,
    :labels_any,
    :issue_types,
    :priority_min,
    :priority_max,
    :has_children,
    :blocked,
    :after
  ]

  # Parent-edge depth is bounded so a recursive walk can never run away. Real trees
  # are about 5 deep; 10 leaves headroom without letting a caller ask for the world.
  @max_depth 10

  @enforce_keys [:order_by]
  defstruct status: nil,
            text: nil,
            project_id: nil,
            project_ids: nil,
            ready: false,
            assigned_to: nil,
            labels: nil,
            order_by: [created_at: :asc, id: :asc],
            limit: nil,
            offset: nil,
            include: [],
            detail: :compact,
            transforms: %{},
            under: nil,
            include_root: false,
            depth: nil,
            fold: false,
            path: false,
            keep_ancestors: false,
            labels_any: nil,
            issue_types: nil,
            priority_min: nil,
            priority_max: nil,
            has_children: nil,
            blocked: nil,
            after: nil

  @type t :: %__MODULE__{
          status: String.t() | nil,
          text: String.t() | nil,
          project_id: String.t() | nil,
          project_ids: [String.t()] | nil,
          ready: boolean(),
          assigned_to: String.t() | nil,
          labels: String.t() | [String.t()] | nil,
          order_by: keyword(:asc | :desc),
          limit: pos_integer() | nil,
          offset: non_neg_integer() | nil,
          include: [:comments | :labels],
          detail: :minimal | :compact | :standard | :full,
          transforms: %{optional(atom()) => {:local, :trim} | {:external, atom()}},
          under: String.t() | pos_integer() | nil,
          include_root: boolean(),
          depth: 0..10 | nil,
          fold: boolean(),
          path: boolean(),
          keep_ancestors: boolean(),
          labels_any: [String.t()] | nil,
          issue_types: [String.t()] | nil,
          priority_min: integer() | nil,
          priority_max: integer() | nil,
          has_children: boolean() | nil,
          blocked: boolean() | nil,
          after: String.t() | nil
        }

  @spec fields() :: [atom()]
  def fields, do: @fields

  @spec new(keyword() | t()) :: {:ok, t()} | {:error, term()}
  def new(%__MODULE__{} = spec), do: validate(spec)

  def new(opts) when is_list(opts) do
    with :ok <- validate_keyword(opts),
         :ok <- validate_fields(opts) do
      opts
      |> Enum.into(%{})
      |> then(&struct(__MODULE__, &1))
      |> validate()
    end
  end

  def new(_), do: {:error, :invalid_spec}

  @spec new!(keyword() | t()) :: t()
  def new!(spec) do
    case new(spec) do
      {:ok, validated} -> validated
      {:error, reason} -> raise ArgumentError, describe_error(reason)
    end
  end

  @spec to_opts(t()) :: keyword()
  def to_opts(%__MODULE__{} = spec) do
    [
      text: spec.text,
      status: spec.status,
      project_id: spec.project_id,
      project_ids: spec.project_ids,
      ready: spec.ready,
      assigned_to: spec.assigned_to,
      labels: spec.labels,
      order_by: spec.order_by,
      limit: spec.limit,
      offset: spec.offset,
      include: spec.include,
      under: spec.under,
      include_root: spec.include_root,
      depth: spec.depth,
      labels_any: spec.labels_any,
      issue_types: spec.issue_types,
      priority_min: spec.priority_min,
      priority_max: spec.priority_max,
      has_children: spec.has_children,
      blocked: spec.blocked
    ]
    |> Enum.reject(fn {_key, value} -> is_nil(value) or value == [] end)
  end

  @doc """
  Validates the filter keys `Bee.count/2` and `Bee.list/2` share with a query spec
  (`under`, `depth`, the label/type/priority ranges, `has_children`, `blocked`), so a
  count can never accept a filter the query it counts would reject.
  """
  @spec validate_filter_opts(keyword()) :: :ok | {:error, term()}
  def validate_filter_opts(opts) do
    with :ok <- validate_under(Keyword.get(opts, :under)),
         :ok <- validate_boolean(:include_root, Keyword.get(opts, :include_root, false)),
         :ok <- validate_depth(Keyword.get(opts, :depth)),
         :ok <- validate_string_list(:labels_any, Keyword.get(opts, :labels_any)),
         :ok <- validate_string_list(:issue_types, Keyword.get(opts, :issue_types)),
         :ok <- validate_integer(:priority_min, Keyword.get(opts, :priority_min)),
         :ok <- validate_integer(:priority_max, Keyword.get(opts, :priority_max)),
         :ok <- validate_optional_boolean(:has_children, Keyword.get(opts, :has_children)) do
      validate_optional_boolean(:blocked, Keyword.get(opts, :blocked))
    end
  end

  defp validate(spec) do
    with :ok <- validate_filter(:text, spec.text),
         :ok <- validate_filter(:status, spec.status),
         :ok <- validate_filter(:project_id, spec.project_id),
         :ok <- validate_project_ids(spec.project_ids),
         :ok <- validate_ready(spec.ready),
         :ok <- validate_filter(:assigned_to, spec.assigned_to),
         :ok <- validate_labels(spec.labels),
         :ok <- validate_order_by(spec.order_by),
         :ok <- validate_limit(spec.limit),
         :ok <- validate_offset(spec.offset),
         :ok <- validate_include(spec.include),
         :ok <- validate_detail(spec.detail),
         :ok <- validate_transforms(spec.transforms),
         :ok <- spec |> Map.from_struct() |> Map.to_list() |> validate_filter_opts(),
         :ok <- validate_boolean(:fold, spec.fold),
         :ok <- validate_boolean(:path, spec.path),
         :ok <- validate_boolean(:keep_ancestors, spec.keep_ancestors),
         :ok <- validate_fold(spec.fold, spec.depth),
         order_by = canonical_order(spec.order_by),
         :ok <- validate_after(spec.after, spec.offset, order_by) do
      {:ok, %{spec | order_by: order_by}}
    end
  end

  defp validate_keyword(opts) do
    if Keyword.keyword?(opts) and Enum.uniq_by(opts, &elem(&1, 0)) == opts,
      do: :ok,
      else: {:error, :invalid_spec}
  end

  defp validate_fields(opts) do
    case Enum.find(opts, fn {key, _value} -> key not in @fields end) do
      nil -> :ok
      {key, _value} -> {:error, {:invalid_spec_field, key}}
    end
  end

  defp validate_filter(_key, nil), do: :ok
  defp validate_filter(_key, value) when is_binary(value), do: :ok
  defp validate_filter(key, value), do: {:error, {:invalid_filter, key, value}}

  defp validate_project_ids(nil), do: :ok

  defp validate_project_ids(project_ids) when is_list(project_ids) and project_ids != [] do
    if Enum.all?(project_ids, &is_binary/1),
      do: :ok,
      else: {:error, {:invalid_filter, :project_ids, project_ids}}
  end

  defp validate_project_ids(project_ids),
    do: {:error, {:invalid_filter, :project_ids, project_ids}}

  defp validate_ready(ready) when is_boolean(ready), do: :ok
  defp validate_ready(ready), do: {:error, {:invalid_filter, :ready, ready}}

  defp validate_labels(nil), do: :ok
  defp validate_labels(label) when is_binary(label), do: :ok

  defp validate_labels(labels) when is_list(labels) and labels != [] do
    if Enum.all?(labels, &is_binary/1), do: :ok, else: {:error, {:invalid_labels, labels}}
  end

  defp validate_labels(labels), do: {:error, {:invalid_labels, labels}}

  defp validate_order_by(order_by) when is_list(order_by) do
    Enum.reduce_while(order_by, :ok, fn
      {column, direction}, _acc
      when column in @order_columns and direction in @order_directions ->
        {:cont, :ok}

      column, _acc when column in @order_columns ->
        {:cont, :ok}

      value, _acc ->
        {:halt, {:error, {:invalid_order_by, value}}}
    end)
  end

  defp validate_order_by(value), do: {:error, {:invalid_order_by, value}}

  defp validate_limit(nil), do: :ok
  defp validate_limit(limit) when is_integer(limit) and limit > 0 and limit <= 500, do: :ok
  defp validate_limit(limit), do: {:error, {:invalid_limit, limit}}

  defp validate_offset(nil), do: :ok
  defp validate_offset(offset) when is_integer(offset) and offset >= 0, do: :ok
  defp validate_offset(offset), do: {:error, {:invalid_offset, offset}}

  defp validate_include(include) when is_list(include) do
    if Enum.all?(include, &(&1 in @include_relations)),
      do: :ok,
      else: {:error, {:invalid_include, include}}
  end

  defp validate_include(include), do: {:error, {:invalid_include, include}}

  defp validate_detail(detail) when detail in @details, do: :ok
  defp validate_detail(detail), do: {:error, {:invalid_detail, detail}}

  defp validate_transforms(transforms) when is_map(transforms) do
    if Enum.all?(transforms, fn
         {field, {:local, :trim}} when is_atom(field) -> true
         {field, {:external, name}} when is_atom(field) and is_atom(name) -> true
         _ -> false
       end),
       do: :ok,
       else: {:error, :invalid_transform}
  end

  defp validate_transforms(_transforms), do: {:error, :invalid_transform}

  defp validate_under(nil), do: :ok
  defp validate_under(id) when is_binary(id) and id != "", do: :ok
  defp validate_under(id) when is_integer(id) and id > 0, do: :ok
  defp validate_under(id), do: {:error, {:invalid_filter, :under, id}}

  defp validate_depth(nil), do: :ok
  defp validate_depth(depth) when is_integer(depth) and depth in 0..@max_depth, do: :ok
  defp validate_depth(depth), do: {:error, {:invalid_depth, depth}}

  defp validate_boolean(_key, value) when is_boolean(value), do: :ok
  defp validate_boolean(key, value), do: {:error, {:invalid_filter, key, value}}

  defp validate_optional_boolean(_key, nil), do: :ok
  defp validate_optional_boolean(key, value), do: validate_boolean(key, value)

  defp validate_integer(_key, nil), do: :ok
  defp validate_integer(_key, value) when is_integer(value), do: :ok
  defp validate_integer(key, value), do: {:error, {:invalid_filter, key, value}}

  defp validate_string_list(_key, nil), do: :ok

  defp validate_string_list(key, values) when is_list(values) and values != [] do
    if Enum.all?(values, &is_binary/1),
      do: :ok,
      else: {:error, {:invalid_filter, key, values}}
  end

  defp validate_string_list(key, values), do: {:error, {:invalid_filter, key, values}}

  # A roll-up describes a folded card in a depth-bounded tree; without a depth there
  # is no fold line, and an unbounded roll-up per row is the cost the spec exists
  # to avoid.
  defp validate_fold(true, nil), do: {:error, :fold_requires_depth}
  defp validate_fold(_fold, _depth), do: :ok

  # Keyset and offset paging answer the same question two incompatible ways.
  defp validate_after(nil, _offset, _order_by), do: :ok

  defp validate_after(_after, offset, _order_by) when not is_nil(offset),
    do: {:error, :after_with_offset}

  defp validate_after(cursor, nil, order_by) do
    case Bee.Query.Cursor.decode(cursor, order_by) do
      {:ok, _values} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp canonical_order([]), do: [id: :asc]

  defp canonical_order(order_by) do
    order_by =
      Enum.map(order_by, fn
        {column, direction} -> {column, direction}
        column -> {column, :asc}
      end)

    if Keyword.has_key?(order_by, :id), do: order_by, else: order_by ++ [id: :asc]
  end

  defp describe_error(:invalid_spec), do: "invalid query spec"

  defp describe_error({:invalid_spec_field, field}),
    do: "invalid query spec field: #{inspect(field)}"

  defp describe_error({:invalid_filter, field, value}), do: "invalid #{field}: #{inspect(value)}"
  defp describe_error({:invalid_labels, value}), do: "invalid labels: #{inspect(value)}"
  defp describe_error({:invalid_order_by, value}), do: "invalid order_by: #{inspect(value)}"
  defp describe_error({:invalid_limit, value}), do: "invalid limit: #{inspect(value)}"
  defp describe_error({:invalid_offset, value}), do: "invalid offset: #{inspect(value)}"
  defp describe_error({:invalid_include, value}), do: "invalid include: #{inspect(value)}"
  defp describe_error({:invalid_detail, value}), do: "invalid detail: #{inspect(value)}"
  defp describe_error(:invalid_transform), do: "invalid transform"
  defp describe_error({:invalid_depth, value}), do: "invalid depth: #{inspect(value)}"
  defp describe_error(:fold_requires_depth), do: "fold requires depth"
  defp describe_error(:after_with_offset), do: "after and offset are mutually exclusive"
  defp describe_error({:invalid_cursor, value}), do: "invalid after cursor: #{inspect(value)}"
end
