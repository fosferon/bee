defmodule Bee.TestSupport.Seam do
  @moduledoc false

  # The working test seam behind `Bee.TestSeam`, compiled only into bee's own test
  # build (test/support is in `elixirc_paths(:test)` and is not part of the package).
  #
  # Repo options:
  #
  #   * `store_fault: point` or `store_fault: {point, :prepare | :step}` makes the real
  #     statement at `point` fail inside the SQLite driver: `:prepare` substitutes SQL
  #     that does not parse, `:step` substitutes SQL that binds the same parameters
  #     and then fails while stepping (integer overflow). Points: `:id_allocation`,
  #     `:issue_insert`, `:label_insert`, `:event_sequence`, `:event_insert` and
  #     `:hydration` on a keyed create; `:lookup` and `:hydration` on
  #     `{:get_by_external_key, key}`.
  #   * `export_observer: pid` receives `{:bee_test_export, :scheduled | :flushed}`.

  def put_state(state, opts) do
    Map.put(state, :test_seam, %{
      store_fault: normalize(Keyword.get(opts, :store_fault)),
      export_observer: Keyword.get(opts, :export_observer)
    })
  end

  def sql(%{store_fault: {point, :prepare}}, point, _sql, _params),
    do: "INJECTED STORE FAULT #{point}"

  def sql(%{store_fault: {point, :step}}, point, _sql, params),
    do: "SELECT abs(-9223372036854775808)" <> String.duplicate(", ?", length(params))

  def sql(_seam, _point, sql, _params), do: sql

  def observe_export(%{export_observer: pid}, event) when is_pid(pid) do
    send(pid, {:bee_test_export, event})
    :ok
  end

  def observe_export(_seam, _event), do: :ok

  defp normalize(nil), do: nil

  defp normalize({point, mode} = fault) when is_atom(point) and mode in [:prepare, :step],
    do: fault

  defp normalize(point) when is_atom(point), do: {point, :prepare}
end
