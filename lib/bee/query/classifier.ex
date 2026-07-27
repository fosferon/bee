defmodule Bee.Query.Classifier do
  @moduledoc false

  @type lane :: :fast | :compute

  @compute_reads [:who_blocks_whom, :agent_load, :bottlenecks]

  @spec classify(atom()) :: lane()
  def classify(read_type) do
    if read_type in @compute_reads, do: :compute, else: :fast
  end
end
