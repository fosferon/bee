defmodule Bee.TestSeam do
  @moduledoc false

  # Fault injection and export observation for bee's own test suite, inert everywhere
  # else.
  #
  # The working implementation, `Bee.TestSupport.Seam`, lives in test/support and is
  # compiled only by bee's own test build (`elixirc_paths(:test)` in bee's mix.exs).
  # The package ships neither test/ nor any other definition of it, and the choice
  # is made here at compile time without reading application configuration. So when
  # bee is built as a dependency, whatever its parent configures, this module is the
  # inert one: `put_state/2` leaves the Repo state unchanged, `sql/4` returns the
  # statement it is given, and `observe_export/2` does nothing. The Repo options
  # `:store_fault` and `:export_observer` then have no effect.

  @impl_module (case Code.ensure_compiled(Bee.TestSupport.Seam) do
                  {:module, module} -> module
                  {:error, _} -> nil
                end)

  if @impl_module do
    defdelegate put_state(state, opts), to: @impl_module
    defdelegate sql(seam, point, sql, params), to: @impl_module
    defdelegate observe_export(seam, event), to: @impl_module
  else
    def put_state(state, _opts), do: state
    def sql(_seam, _point, sql, _params), do: sql
    def observe_export(_seam, _event), do: :ok
  end
end
