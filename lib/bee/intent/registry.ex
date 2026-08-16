defmodule Bee.Intent.Registry do
  @moduledoc false

  alias Bee.Query.Spec

  @spec register(Exqlite.Sqlite3.db(), String.t(), keyword() | Spec.t()) :: :ok | {:error, term()}
  def register(conn, name, spec) when is_binary(name) and name != "" do
    with {:ok, spec} <- Spec.new(spec),
         {:ok, json} <- Jason.encode(encode_spec(spec)) do
      Bee.Store.Intents.put(conn, name, json)
    end
  end

  def register(_conn, _name, _spec), do: {:error, :invalid_spec}

  @spec resolve(Exqlite.Sqlite3.db(), String.t()) :: {:ok, Spec.t()} | {:error, term()}
  def resolve(conn, name) do
    with {:ok, json} <- Bee.Store.Intents.get(conn, name),
         {:ok, encoded} <- Jason.decode(json),
         {:ok, spec} <- decode_spec(encoded) do
      {:ok, spec}
    else
      {:error, _reason} = error -> error
      _ -> {:error, :invalid_spec}
    end
  end

  @spec remove(Exqlite.Sqlite3.db(), String.t()) :: :ok
  def remove(conn, name), do: Bee.Store.Intents.delete(conn, name)

  @spec list(Exqlite.Sqlite3.db()) :: {:ok, [map()]} | {:error, term()}
  def list(conn), do: Bee.Store.Intents.list(conn)

  defp encode_spec(spec) do
    %{
      "text" => spec.text,
      "status" => spec.status,
      "project_id" => spec.project_id,
      "project_ids" => spec.project_ids,
      "ready" => spec.ready,
      "assigned_to" => spec.assigned_to,
      "labels" => spec.labels,
      "order_by" => Enum.map(spec.order_by, fn {field, direction} -> [field, direction] end),
      "limit" => spec.limit,
      "offset" => spec.offset,
      "include" => Enum.map(spec.include, &Atom.to_string/1),
      "detail" => spec.detail,
      "transforms" => encode_transforms(spec.transforms)
    }
  end

  defp decode_spec(encoded) do
    with {:ok, order_by} <- decode_order_by(Map.get(encoded, "order_by")),
         {:ok, include} <- decode_atoms(Map.get(encoded, "include", [])),
         {:ok, detail} <- decode_detail(Map.get(encoded, "detail", "compact")),
         {:ok, transforms} <- decode_transforms(Map.get(encoded, "transforms", %{})) do
      Spec.new(
        text: Map.get(encoded, "text"),
        status: Map.get(encoded, "status"),
        project_id: Map.get(encoded, "project_id"),
        project_ids: Map.get(encoded, "project_ids"),
        ready: Map.get(encoded, "ready", false),
        assigned_to: Map.get(encoded, "assigned_to"),
        labels: Map.get(encoded, "labels"),
        order_by: order_by,
        limit: Map.get(encoded, "limit"),
        offset: Map.get(encoded, "offset"),
        include: include,
        detail: detail,
        transforms: transforms
      )
    end
  end

  defp decode_order_by(order_by) when is_list(order_by) do
    Enum.reduce_while(order_by, {:ok, []}, fn
      [field, direction], {:ok, acc} when is_binary(field) and is_binary(direction) ->
        {:cont,
         {:ok, [{String.to_existing_atom(field), String.to_existing_atom(direction)} | acc]}}

      _, _ ->
        {:halt, {:error, :invalid_spec}}
    end)
    |> case do
      {:ok, order_by} -> {:ok, Enum.reverse(order_by)}
      error -> error
    end
  rescue
    ArgumentError -> {:error, :invalid_spec}
  end

  defp decode_order_by(_), do: {:error, :invalid_spec}

  defp decode_atoms(values) when is_list(values) do
    {:ok, Enum.map(values, &String.to_existing_atom/1)}
  rescue
    ArgumentError -> {:error, :invalid_spec}
  end

  defp decode_atoms(_), do: {:error, :invalid_spec}

  defp decode_detail(detail) when is_binary(detail) do
    {:ok, String.to_existing_atom(detail)}
  rescue
    ArgumentError -> {:error, :invalid_spec}
  end

  defp decode_detail(detail), do: {:ok, detail}

  defp encode_transforms(transforms) do
    Map.new(transforms, fn {field, {tier, name}} ->
      {Atom.to_string(field), [Atom.to_string(tier), Atom.to_string(name)]}
    end)
  end

  defp decode_transforms(transforms) when is_map(transforms) do
    Enum.reduce_while(transforms, {:ok, %{}}, fn
      {field, [tier, name]}, {:ok, acc}
      when is_binary(field) and is_binary(tier) and is_binary(name) ->
        try do
          transform = {String.to_existing_atom(tier), String.to_existing_atom(name)}
          {:cont, {:ok, Map.put(acc, String.to_existing_atom(field), transform)}}
        rescue
          ArgumentError -> {:halt, {:error, :invalid_spec}}
        end

      _, _ ->
        {:halt, {:error, :invalid_spec}}
    end)
  end

  defp decode_transforms(_), do: {:error, :invalid_spec}
end
