defmodule Bee.Query.Spec do
  @moduledoc false

  @order_columns ~w(created_at updated_at priority id)a
  @order_directions [:asc, :desc]
  @include_relations [:comments]
  @fields [:status, :project_id, :assigned_to, :labels, :order_by, :limit, :offset, :include]

  @enforce_keys [:order_by]
  defstruct status: nil,
            project_id: nil,
            assigned_to: nil,
            labels: nil,
            order_by: [created_at: :asc, id: :asc],
            limit: nil,
            offset: nil,
            include: []

  @type t :: %__MODULE__{
          status: String.t() | nil,
          project_id: String.t() | nil,
          assigned_to: String.t() | nil,
          labels: String.t() | [String.t()] | nil,
          order_by: keyword(:asc | :desc),
          limit: pos_integer() | nil,
          offset: non_neg_integer() | nil,
          include: [:comments]
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
      status: spec.status,
      project_id: spec.project_id,
      assigned_to: spec.assigned_to,
      labels: spec.labels,
      order_by: spec.order_by,
      limit: spec.limit,
      offset: spec.offset,
      include: spec.include
    ]
    |> Enum.reject(fn {_key, value} -> is_nil(value) or value == [] end)
  end

  defp validate(spec) do
    with :ok <- validate_filter(:status, spec.status),
         :ok <- validate_filter(:project_id, spec.project_id),
         :ok <- validate_filter(:assigned_to, spec.assigned_to),
         :ok <- validate_labels(spec.labels),
         :ok <- validate_order_by(spec.order_by),
         :ok <- validate_limit(spec.limit),
         :ok <- validate_offset(spec.offset),
         :ok <- validate_include(spec.include) do
      {:ok, %{spec | order_by: canonical_order(spec.order_by)}}
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
  defp validate_limit(limit) when is_integer(limit) and limit > 0, do: :ok
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
end
