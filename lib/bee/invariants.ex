defmodule Bee.Invariants do
  @moduledoc """
  Silent-failure invariant (Story 3.6, NFR10, G27).

  ## Rule

  No operation in Bee may fail silently. Every failure must either:
  - return a tagged error from the closed vocabulary,
  - log a warning/error, or
  - fall back to a documented default.

  ## Enumerated exceptions (closed list)

  The following **three** cases are the only exceptions where a failure
  produces no observable signal. Each is justified by an inherent
  limitation of the brutal-kill path. The list is closed — new code
  paths that would fail silently are rejected unless added here with
  a stated reason.

  ### 1. Sweeper in-flight write on brutal kill (Story 3.5)

  The Sweeper dispatches a lock-expiry write to the Repo via
  `GenServer.call/3`. If the Repo is brutally killed while processing
  that call, the in-flight write is lost. The lock remains in the
  `locks` table with an expired `expires_at`.

  **Why silent:** The brutal-kill path does not run `terminate/2`,
  so there is no cleanup hook to log or retry.

  **Recovery:** The next sweep cycle (60s timer) re-dispatches expiry
  for the still-expired lock. The release + event transaction is
  idempotent (cascade F3).

  ### 2. JSONL export window on brutal kill (Story 3.4)

  The debounced JSONL export accumulates writes and flushes after a
  5s debounce. If the Repo is brutally killed with a pending flush
  or mid-flush, the un-flushed event window is lost.

  **Why silent:** The brutal-kill path does not run `terminate/2`,
  so the final flush in `terminate/2` does not execute.

  **Recovery:** The JSONL trail is derived from the DB, not a primary
  log. A re-export regenerates the complete trail from current DB
  state. The loss is a staleness gap, not a data-loss gap.

  ### 3. WAL TRUNCATE checkpoint failure at terminate (Story 3.2)

  The `terminate/2` callback attempts a `PRAGMA wal_checkpoint(TRUNCATE)`.
  If this fails (e.g., the connection is in a degraded state after a
  trapped crash), the WAL retains uncommitted pages.

  **Why silent:** `terminate/2` catches the checkpoint failure and
  logs a warning, but the WAL itself is not checkpointed. The
  warning is the observable signal, but the uncheckpointed WAL is
  the silent consequence.

  **Recovery:** The next boot's PASSIVE checkpoint timer (60s)
  checkpoints the WAL. WAL mode ensures the DB is consistent
  regardless of checkpoint state.
  """

  @silent_failure_exceptions [
    %{
      id: :sweeper_in_flight_write,
      story: "3.5",
      reason: "Brutal kill of Repo mid-sweep loses in-flight lock-expiry write",
      recovery: "Next sweep cycle re-dispatches (idempotent, cascade F3)"
    },
    %{
      id: :jsonl_export_window,
      story: "3.4",
      reason: "Brutal kill with pending debounce flush loses un-flushed event window",
      recovery: "JSONL is derived from DB; re-export regenerates complete trail"
    },
    %{
      id: :wal_truncate_failure,
      story: "3.2",
      reason: "TRUNCATE checkpoint failure in terminate leaves WAL uncheckpointed",
      recovery: "Next boot's PASSIVE checkpoint timer (60s) recovers"
    }
  ]

  @doc """
  Returns the closed list of silent-failure exceptions.
  """
  @spec silent_failure_exceptions() :: [map()]
  def silent_failure_exceptions, do: @silent_failure_exceptions

  @doc """
  Validates that a given failure path is in the enumerated exception list.

  Raises if the path is not listed — used by reviewers to enforce the
  closed-list invariant.
  """
  @spec assert_enumerated!(atom()) :: :ok
  def assert_enumerated!(id) do
    unless Enum.any?(@silent_failure_exceptions, &(&1.id == id)) do
      raise ArgumentError,
            "Silent failure path #{inspect(id)} is not in the enumerated exception list. " <>
              "Add it to Bee.Invariants with a stated reason, or handle the failure explicitly."
    end

    :ok
  end
end
