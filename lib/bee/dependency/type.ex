defmodule Bee.Dependency.Type do
  @moduledoc false

  @gating [:blocks, :waits_for, :conditional_blocks]
  @non_gating [:related, :discovered_from, :replies_to]
  @unwritable [:parent_child]
  @writable @gating ++ @non_gating
  @types @writable ++ @unwritable

  @spec all() :: [atom()]
  def all, do: @types

  @spec gating() :: [atom()]
  def gating, do: @gating

  @spec validate(atom()) :: :ok | {:error, :unknown_dep_type | :unwritable_dep_type}
  def validate(type) when type in @writable, do: :ok
  def validate(type) when type in @unwritable, do: {:error, :unwritable_dep_type}
  def validate(_type), do: {:error, :unknown_dep_type}

  @spec storage_name(atom()) :: String.t()
  def storage_name(type) when type in @types, do: type |> Atom.to_string() |> String.replace("_", "-")
end
