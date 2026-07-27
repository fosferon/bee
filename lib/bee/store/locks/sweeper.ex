defmodule Bee.Store.Locks.Sweeper do
  @moduledoc false
  use GenServer
  require Logger

  @sweep_interval_ms 60_000

  @doc """
  Starts the lock sweeper.

  The sweeper holds no DB connection of its own (Story 3.5, G13).
  It dispatches lock-expiry operations to Bee.Repo (the writer).
  """
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
    # Dispatch through the writer — no connection of our own (Story 3.5, G13).
    # One event per expired lock, not one per sweep (Story 3.5, G13).
    try do
      swept = GenServer.call(state.repo, :sweep_expired_locks, 30_000)
      if swept > 0, do: Logger.info("Lock sweeper reclaimed #{swept} expired locks")
    catch
      :exit, reason ->
        Logger.warning("Lock sweeper dispatch failed: #{inspect(reason)}")
    end

    schedule_sweep(state.interval)
    {:noreply, state}
  end

  defp schedule_sweep(interval) do
    Process.send_after(self(), :sweep, interval)
  end
end
