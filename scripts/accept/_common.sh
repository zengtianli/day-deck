#!/bin/bash
# Shared, noninteractive acceptance entry points. Never installs or launches UI.
set -euo pipefail
ACCEPT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ACCEPT_ROOT"

accept_swift_tests() (
  local filter="$1"
  local log scratch owned=0
  scratch="${NOTIHUB_ACCEPT_SCRATCH:-}"
  if [[ -z "$scratch" ]]; then
    scratch="$(mktemp -d /private/tmp/notihub-swiftpm-accept.XXXXXX)"
    owned=1
  fi
  # Caller caches are retained; cleanup only this invocation's own new scratch.
  trap '[[ -z "${log:-}" ]] || rm -f "$log"; [[ "$owned" == 0 ]] || rm -rf "$scratch"' EXIT
  "$HOME/Dev/.venv/bin/python" - "$scratch" "$ACCEPT_ROOT" "$owned" <<'PY'
import fcntl, hashlib, json, os, stat, sys
from pathlib import Path
if any(value for key, value in os.environ.items() if 'gate' in key.lower() and any(part in key.lower() for part in ('pw', 'password', 'credential'))):
    raise SystemExit('acceptance refuses inherited launch credentials')
p, repo = Path(sys.argv[1]), Path(sys.argv[2]).resolve()
if not p.is_absolute() or p.is_symlink() or not p.is_dir():
    raise SystemExit('acceptance scratch must be an existing absolute private directory')
p = p.resolve()
if p.is_relative_to(repo) or repo.is_relative_to(p):
    raise SystemExit('acceptance scratch must be outside the source tree')
s = p.stat()
if s.st_uid != os.getuid() or stat.S_IMODE(s.st_mode) & 0o077:
    raise SystemExit('acceptance scratch must be owned by this user with private permissions')
if sys.argv[3] == '0':
    proof_path = Path(os.environ.get('NOTIHUB_ACCEPT_SCRATCH_PROOF', ''))
    if not proof_path.is_absolute() or proof_path.is_symlink() or not proof_path.is_file():
        raise SystemExit('caller scratch requires its original source/toolchain/lock proof')
    proof = json.loads(proof_path.read_text())
    if proof['repo'] != str(repo) or proof['scratch'] != str(p):
        raise SystemExit('caller scratch proof path mismatch')
    sys.path.insert(0, str(Path.home()/'Apps/chapter/engine'))
    import app_sop
    app = app_sop.load_apps('day-deck-ios')[0]
    current = {**app_sop.lane_inputs(app, 'iphone')['files'],
               **app_sop.app_source_snapshot(app, app['sop']['test_inputs'], True)['files']}
    if proof['files'] != current:
        raise SystemExit('caller scratch does not bind the complete current source/test input map')
    owner = json.loads((Path.home()/'Library/Caches/sim-lane/lock/sim_lane.json').read_text())
    if owner['pid'] != proof['owner_pid']:
        raise SystemExit('caller scratch is not under its original directory lock')
    os.kill(proof['owner_pid'], 0)
    with (Path.home()/'Library/Application Support/app-sop/lock').open('a+') as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            pass
        else:
            raise SystemExit('caller scratch is not under the original NB global lock')
    for key, expected in proof['files'].items():
        file = Path(key)
        if file.is_absolute() or '..' in file.parts or hashlib.sha256((repo/file).read_bytes()).hexdigest() != expected:
            raise SystemExit('caller scratch source binding changed')
    compiler = Path(proof['swift'])
    if os.environ.get('DEVELOPER_DIR') != proof['developer_dir'] or hashlib.sha256(compiler.read_bytes()).hexdigest() != proof['swift_sha256']:
        raise SystemExit('caller scratch toolchain binding changed')
PY
  log="$(mktemp -t notihub-accept)"
  if ! xcrun swift test --scratch-path "$scratch" -j 2 --filter "$filter" >"$log" 2>&1; then
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
)

accept_scope() {
  ACCEPT_DESCRIPTION="$*"
  printf '%s\n' "$*"
}
