defmodule Bee.TestSupport.Seam do
  @moduledoc false

  # The working test seam behind `Bee.TestSeam`, compiled only into bee's own test
  # build (test/support is in `elixirc_paths(:test)` and is not part of the package).
  #
  # Repo options: `store_fault: point` makes `fault/2` fail at `point`;
  # `export_observer: pid` receives `{:bee_test_export, :scheduled | :flushed}`.

  def put_state(state, opts) do
    Map.put(state, :test_seam, %{
      store_fault: Keyword.get(opts, :store_fault),
      export_observer: Keyword.get(opts, :export_observer)
    })
  end

  def fault(%{store_fault: point}, point), do: {:error, "injected store fault: #{point}"}
  def fault(_seam, _point), do: :ok

  def observe_export(%{export_observer: pid}, event) when is_pid(pid) do
    send(pid, {:bee_test_export, event})
    :ok
  end

  def observe_export(_seam, _event), do: :ok
end
