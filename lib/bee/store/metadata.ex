defmodule Bee.Store.Metadata do
  @moduledoc false

  @spec encode(map()) :: {:ok, String.t()} | {:error, :invalid_metadata | :reserved_metadata_key}
  def encode(metadata) when is_map(metadata) do
    if Enum.all?(metadata, fn {key, _value} -> is_binary(key) end) do
      if Enum.any?(Map.keys(metadata), &String.starts_with?(&1, "bee:")) do
        {:error, :reserved_metadata_key}
      else
        {:ok, Jason.encode!(metadata)}
      end
    else
      {:error, :invalid_metadata}
    end
  end

  def encode(_metadata), do: {:error, :invalid_metadata}

  @spec decode(String.t() | nil) :: map()
  def decode(nil), do: %{}
  def decode(value) when is_binary(value), do: Jason.decode!(value)
end
