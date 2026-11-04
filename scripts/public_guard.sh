#!/usr/bin/env bash
# public_guard.sh: refuse to publish internal material from this public repo.
#
# Scans every tracked file for personal paths, private addresses, internal issue
# references and AI-tool/working-paper artefacts. Extra patterns that must not
# themselves be published (client names) are read from PUBLIC_GUARD_EXTRA
# (one ERE per line) or from $PUBLIC_GUARD_EXTRA_FILE. Exit 1 on any finding.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

self='^scripts/public_guard(_test)?\.sh$'
patterns=(
  '/Users/[A-Za-z]'
  '/home/[a-z]+/'
  '[A-Za-z0-9._%+-]+@gmail\.com'
  '\b192\.168\.[0-9]+\.[0-9]+'
  '\b10\.[0-9]+\.[0-9]+\.[0-9]+'
  '\bGC-[0-9]+'
)
extra="${PUBLIC_GUARD_EXTRA:-}"
if [[ -z "$extra" && -n "${PUBLIC_GUARD_EXTRA_FILE:-}" && -r "$PUBLIC_GUARD_EXTRA_FILE" ]]; then
  extra="$(cat "$PUBLIC_GUARD_EXTRA_FILE")"
fi
while IFS= read -r p; do [[ -n "$p" && "$p" != \#* ]] && patterns+=("$p"); done <<< "$extra"

fail=0
# NUL-delimited end to end: unusual file names are scanned, never skipped.
list_files() { git ls-files -z | grep -zEv "$self" || true; }
names=$(git -c core.quotePath=false ls-files | grep -Ev "$self" || true)

artefacts=$(echo "$names" | grep -E '(^|/)(CLAUDE\.md|AGENTS\.md|\.claude/|\.serena/|\.devman/|_bmad[^/]*/|\.planning/|\.cursor/|\.swarm/)' || true)
papers=$(echo "$names" | grep -E '^[A-Z0-9_]+\.md$' | grep -Ev '^(README|CHANGELOG|LICENSE|CONTRIBUTING|SECURITY|CODE_OF_CONDUCT)\.md$' || true)
if [[ -n "$artefacts$papers" ]]; then
  echo "public_guard: internal artefacts or working papers are tracked:"; printf "%s\n%s\n" "$artefacts" "$papers" | sed '/^$/d; s/^/  /'
  fail=1
fi

for p in "${patterns[@]}"; do
  errf=$(mktemp)
  hits=$(list_files | xargs -0 -r grep -I -n -i -E -- "$p" 2>"$errf" || true)
  # Exit codes differ between GNU and BSD xargs; any grep diagnostic is a scan error.
  if [[ -s "$errf" ]]; then
    echo "public_guard: scan error for pattern: $p"; sed 's/^/  /' "$errf"; rm -f "$errf"; fail=1; continue
  fi
  rm -f "$errf"
  if [[ -n "$hits" ]]; then
    echo "public_guard: forbidden pattern found:"; echo "$hits" | head -20 | sed 's/^/  /'
    fail=1
  fi
done

[[ $fail -eq 0 ]] && echo "public_guard: clean"
exit $fail
