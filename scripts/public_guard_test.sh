#!/usr/bin/env bash
# Fixture test for public_guard.sh: every pattern class must still trip, and a
# clean tree must pass, so that editing a pattern cannot silently disable it.
set -uo pipefail
guard="$(cd "$(dirname "$0")" && pwd)/public_guard.sh"
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
cd "$work" && git init -q . && git config user.email t@t && git config user.name t
mkdir scripts && cp "$guard" scripts/public_guard.sh

expect() { # expect <0|1> <description>
  PUBLIC_GUARD_EXTRA="${EXTRA:-}" bash scripts/public_guard.sh >/dev/null 2>&1; got=$?
  if [[ $got -ne $1 ]]; then echo "FAIL: $2 (exit $got, expected $1)"; exit 1; fi
  echo "ok: $2"
}
reset() { git rm -rq --cached . >/dev/null 2>&1; find . -mindepth 1 -maxdepth 1 ! -name .git ! -name scripts -exec rm -rf {} +; git add scripts; }
add() { mkdir -p "$(dirname "$1")"; printf '%s\n' "$2" > "$1"; git add "$1"; }

reset; add lib/a.ex 'defmodule A, do: nil';                         expect 0 "clean tree passes"
reset; add lib/a.ex "path = \"/Us""ers/someone/x\"";                  expect 1 "personal macOS path"
reset; add lib/a.ex "mail = \"x@gm""ail.com\"";                       expect 1 "personal email"
reset; add lib/a.ex "url = \"http://192.""168.1.5:80\"";               expect 1 "LAN address"
reset; add lib/a.ex "path = \"/ho""me/someone/x\"";                 expect 1 "personal Linux path"
reset; add lib/a.ex "host = \"10.""0.0.7\"";                          expect 1 "private 10.x address"
reset; add lib/a.ex "# fixed in G""C-1234";                            expect 1 "internal issue reference"
reset; add CLAUDE.md 'x';                                              expect 1 "AI-tool artefact"
reset; add _bmad-output/x.md 'x';                                      expect 1 "planning artefact"
reset; add PARITY_AUDIT.md 'x';                                        expect 1 "root working paper"
reset; add lib/a.ex 'client = "Acmecorp"'; EXTRA='acmecorp'            expect 1 "extra (secret) pattern"
EXTRA=''
reset; add "lib/odd \"näme\".ex" "path = \"/Us""ers/someone/x\"";        expect 1 "file with special characters in its name"
reset; add lib/a.ex "defmodule A, do: nil"; EXTRA="("                    expect 1 "invalid pattern fails closed"
EXTRA=""
echo "public_guard_test: all passed"
