defmodule Bee.Query.Transform do
  @moduledoc false

  @table __MODULE__

  @spec register(atom(), (term() -> term())) :: :ok | {:error, :invalid_transform}
  def register(name, fun) when is_atom(name) and is_function(fun, 1) do
    ensure_table()
    true = :ets.insert(@table, {name, fun})
    :ok
  end

  def register(_name, _fun), do: {:error, :invalid_transform}

  @spec remove(atom()) :: :ok
  def remove(name) when is_atom(name) do
    ensure_table()
    true = :ets.delete(@table, name)
    :ok
  end

  @spec apply(map(), map()) :: {map(), map()}
  def apply(issue, transforms) do
    Enum.reduce(transforms, {issue, %{}}, fn {field, transform}, {issue, applied} ->
      case apply_one(Map.get(issue, field), transform) do
        {:ok, value, descriptor} ->
          {Map.put(issue, field, value), Map.put(applied, field, descriptor)}

        :error ->
          {issue, applied}
      end
    end)
  end

  defp apply_one(value, {:local, :trim}) when is_binary(value),
    do: {:ok, String.trim(value), %{operation: :trim, tier: :local}}

  defp apply_one(value, {:external, name}) do
    ensure_table()

    case :ets.lookup(@table, name) do
      [{^name, fun}] ->
        try do
          {:ok, fun.(value), %{operation: name, tier: :external}}
        rescue
          _ -> :error
        end

      [] ->
        :error
    end
  end

  defp apply_one(_value, _transform), do: :error

  defp ensure_table do
    case :ets.whereis(@table) do
      :undefined -> :ets.new(@table, [:named_table, :public, :set])
      _ -> @table
    end
  end
end
