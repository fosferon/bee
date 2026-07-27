defmodule Bee.Store.Locks.Sweeper do
  @moduledoc false
  use GenServer

  @sweep_interval_ms 60_000

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name))
  end

  @impl true
  def init(opts) do
    state = %{
      repo: Keyword.get(opts, :repo, Bee.Repo),
      interval: Keyword.get(opts, :interval, @sweep_interval_ms)
    }

    schedule_sweep(state.interval)
    {:ok, state}
  end

  @impl true
  def handle_info(:sweep, state) do
    # Story 3.5: sweep expired locks here
    schedule_sweep(state.interval)
    {:noreply, state}
  end

  defp schedule_sweep(interval) do
    Process.send_after(self(), :sweep, interval)
  end
end
