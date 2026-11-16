defmodule Bee.TestSeam do
  @moduledoc false

  # Fault injection and export observation for bee's own test suite.
  #
  # The working clauses are compiled in only when `config :bee, test_faults: true` is
  # set at compile time, which bee's config/config.exs does for its test environment
  # alone. In every other build, including bee compiled as a dependency, `put_state/2`
  # leaves the Repo state untouched and the other functions are constant no-ops, so
  # neither a `:store_fault` nor an `:export_observer` option has any effect.
  #
  # Fault points: `:issue_insert`, `:label_insert` and `:event_record` on a keyed
  # create, and `:lookup` on `{:get_by_external_key, key}`. The observer pid receives
  # `{:bee_test_export, :scheduled | :flushed}`.

  @enabled Application.compile_env(:bee, :test_faults, false)

  if @enabled do
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
  else
    def put_state(state, _opts), do: state
    def fault(_seam, _point), do: :ok
    def observe_export(_seam, _event), do: :ok
  end
end
