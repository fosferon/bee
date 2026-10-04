# GC-5791 Bee owner-port review

The BMad Blind Hunter, Edge Case Hunter and Acceptance Auditor reviewed this
staged increment independently. All confirmed findings were fixed:

- Both default and fenced import modes apply one decoded snapshot in an owner
  transaction. Failed import never advances the ID counter or leaves earlier
  rows applied; subsequent create remains usable.
- Complete import targets include current stored parents and both endpoints of
  incident dependency edges, as well as every incoming target.
- SQL upsert retains issue/event identity instead of deleting the old row.
  Issue/label errors propagate, preserving atomic rollback and comment history
  on failure. Successful imports actually update the intended row.
- Prepared import/sweep messages are denied before either mode's dispatcher;
  only the qualified owner wrapper calls their private handlers.

One sweeper finding was retracted: the original Lock.sweep_expired already emitted
no command events. Its contradictory stale Repo comment was corrected; the
fenced sweep retains the actual legacy result/event contract.

Full final Bee suite: 250 tests, zero failures, one existing performance exclusion.
Log: /private/tmp/gc-5791-bee-owner-final-suite.log. Independent acceptance reruns:
import target12/0, rollback11/0, prepared protocol11/0. Edge probes also verified
label-trigger failure rollback in BOTH fence modes and preserved graph endpoints.
Formatting/diff checks pass. No publication, HTTP/worker cutover, credential or
deployment operation is included. This is not GC-5791, G1 or G2 acceptance.
