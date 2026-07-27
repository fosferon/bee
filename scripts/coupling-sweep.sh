#!/usr/bin/env bash
#
# coupling-sweep.sh — No-consumer-DDL guard (Story 2.7, AD-15)
#
# Greps consumer repos for DDL and references targeting Bee's schema objects.
# Fails if an unknown coupling is found.
#
# Usage: scripts/coupling-sweep.sh [bee_repo_path] [consumer_repo_path...]
#
# Exit codes:
#   0 — no unknown couplings found
#   1 — unknown coupling detected (commit should fail)
#   2 — configuration error

set -euo pipefail

BEE_REPO="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
shift || true
CONSUMER_REPOS=("$@")

# Auto-discover consumer repos if not provided
if [ ${#CONSUMER_REPOS[@]} -eq 0 ]; then
  for candidate in \
    "$(dirname "$(dirname "$BEE_REPO")")/gc_daemon" \
    "$(dirname "$BEE_REPO")/gc_daemon" \
    "$(dirname "$BEE_REPO")/dev_man"; do
    if [ -d "$candidate/lib" ]; then
      CONSUMER_REPOS+=("$candidate")
    fi
  done
fi

if [ ${#CONSUMER_REPOS[@]} -eq 0 ]; then
  echo "coupling-sweep: no consumer repos found, skipping"
  exit 0
fi

# --- Bee's schema objects (only these are in scope) ---

# Tables that migrations 001-004 alter, rebuild, or create.
# (Migration 000 is already merged; its objects are in DROPPED_TABLES or KNOWN_REMOVED.)
MIGRATION_TARGET_TABLES=(
  "issues"
  "dependencies"
  "issues_fts"
  "issue_labels"
  "events"
  "measurements"
  "intents"
  "measures"
  "intent_usage"
)

# Tables dropped by migrations (any reference is a coupling)
DROPPED_TABLES=(
  "labels"
  "issue_project_backfill_log"
)

# --- Known-and-removed couplings (addressed in Epic 1+2) ---
# These patterns are EXPECTED and will NOT fail the sweep.
KNOWN_REMOVED_PATTERNS=(
  "SearchIndex"
  "rebuild_fts"
  "canonical_issues_fts"
  "bee-merge"
  "issue_project_backfill_log"
  "work_handler"
)

FAILURES=0

is_known_removed() {
  local match="$1"
  for pattern in "${KNOWN_REMOVED_PATTERNS[@]}"; do
    if [[ "$match" == *"$pattern"* ]]; then
      return 0
    fi
  done
  return 1
}

check_repo() {
  local repo="$1"
  local repo_base
  repo_base="$(basename "$repo")"

  if [ ! -d "$repo/lib" ]; then
    return
  fi

  echo "--- Sweeping $repo_base ---"

  # 1. DDL targeting Bee's migration-touched tables
  for table in "${MIGRATION_TARGET_TABLES[@]}" "${DROPPED_TABLES[@]}"; do
    local ddl_matches
    ddl_matches=$(grep -rn \
      -E "(CREATE TABLE|ALTER TABLE|DROP TABLE|CREATE INDEX|DROP INDEX|CREATE TRIGGER|DROP TRIGGER|CREATE VIRTUAL TABLE).*\b${table}\b" \
      "$repo/lib" --include="*.ex" 2>/dev/null || true)

    if [ -n "$ddl_matches" ]; then
      while IFS= read -r line; do
        if is_known_removed "$line"; then
          continue
        fi
        echo "  DDL ON BEE TABLE: $line"
        FAILURES=$((FAILURES + 1))
      done <<< "$ddl_matches"
    fi
  done

  # 2. References to dropped tables in SQL context (FROM, JOIN, INSERT INTO, etc.)
  for table in "${DROPPED_TABLES[@]}"; do
    local ref_matches
    ref_matches=$(grep -rn \
      -E "(FROM|JOIN|INSERT INTO|UPDATE|DELETE FROM)\s+${table}\b" \
      "$repo/lib" --include="*.ex" 2>/dev/null || true)

    if [ -n "$ref_matches" ]; then
      while IFS= read -r line; do
        if is_known_removed "$line"; then
          continue
        fi
        echo "  DROPPED TABLE REF ($table): $line"
        FAILURES=$((FAILURES + 1))
      done <<< "$ref_matches"
    fi
  done

  # 3. ALTER TABLE on Bee's projects table (the specific consumer-injection pattern)
  local alter_matches
  alter_matches=$(grep -rn \
    -E "ALTER TABLE\s+projects\b" \
    "$repo/lib" --include="*.ex" 2>/dev/null || true)

  if [ -n "$alter_matches" ]; then
    while IFS= read -r line; do
      if is_known_removed "$line"; then
        continue
      fi
      echo "  ALTER TABLE projects: $line"
      FAILURES=$((FAILURES + 1))
    done <<< "$alter_matches"
  fi
}

echo "=== Coupling Sweep (Story 2.7) ==="
echo "Bee repo: $BEE_REPO"
echo "Consumer repos: ${CONSUMER_REPOS[*]}"
echo ""

for repo in "${CONSUMER_REPOS[@]}"; do
  check_repo "$repo"
done

echo ""
echo "=== Summary ==="
echo "Failures (unknown couplings): $FAILURES"

if [ "$FAILURES" -gt 0 ]; then
  echo ""
  echo "BLOCKED: $FAILURES unknown consumer coupling(s) detected."
  echo "Either remove the coupling in the consumer repo, or add it to"
  echo "KNOWN_REMOVED_PATTERNS in scripts/coupling-sweep.sh if already addressed."
  exit 1
fi

echo "PASS: No unknown couplings detected."
exit 0
