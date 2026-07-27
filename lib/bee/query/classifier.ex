defmodule Bee.Query.Classifier do
  @moduledoc false

  @type lane :: :fast | :compute

  @compute_reads [:who_blocks_whom, :agent_load, :bottlenecks]
  @field_lanes %{
    status: :fast,
    project_id: :fast,
    assigned_to: :fast,
    labels: :fast,
    order_by: :fast,
    limit: :fast,
    offset: :fast,
    include: :fast,
    detail: :fast,
    transforms: :compute
  }

  @spec classify(atom()) :: lane()
  def classify(read_type) when is_atom(read_type) do
    if read_type in @compute_reads, do: :compute, else: :fast
  end

  @spec classify(Bee.Query.Spec.t()) :: lane()
  def classify(%Bee.Query.Spec{transforms: transforms}) when map_size(transforms) > 0, do: :compute
  def classify(%Bee.Query.Spec{}), do: :fast

  @spec field_lanes() :: %{atom() => lane()}
  def field_lanes, do: @field_lanes

  @spec assert_spec_coverage!() :: :ok
  def assert_spec_coverage! do
    fields = Map.keys(@field_lanes) |> MapSet.new()
    expected = Bee.Query.Spec.fields() |> MapSet.new()

    if fields == expected do
      :ok
    else
      raise ArgumentError, "query classifier coverage does not match query spec fields"
    end
  end
end
