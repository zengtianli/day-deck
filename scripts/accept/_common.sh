#!/bin/bash
# Shared, noninteractive acceptance entry points. Never installs or launches UI.
set -euo pipefail
ACCEPT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ACCEPT_ROOT"

accept_swift_tests() {
  local filter="$1"
  local log
  log="$(mktemp -t notihub-accept)"
  if ! xcrun swift test -j 2 --filter "$filter" >"$log" 2>&1; then
    cat "$log"
    rm -f "$log"
    return 1
  fi
  cat "$log"
  # SwiftPM returns zero even when a renamed filter selects no tests.
  if ! grep -Eq 'Executed [1-9][0-9]* tests?, with 0 failures' "$log"; then
    rm -f "$log"
    printf '%s\n' "No XCTest cases executed for $filter" >&2
    return 1
  fi
  rm -f "$log"
  printf 'PASS %s\n' "${ACCEPT_DESCRIPTION:-$filter}"
}

accept_scope() {
  ACCEPT_DESCRIPTION="$*"
  printf '%s\n' "$*"
}
