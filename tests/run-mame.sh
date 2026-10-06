#!/usr/bin/env bash
# run-mame.sh -- run a Lua test against a ROM in MAME with the FujiNet NES slot.
#
#   tests/run-mame.sh ebtest                     the end-to-end save/load test
#   tests/run-mame.sh nocart                     plain NROM slot: NO FUJINET path
#   EB_LOG=... tests/run-mame.sh sfxdiff [rom]   APU log for the sound check
#   MAME=~/src/mame SECS=300 tests/run-mame.sh ebtest
#
# ebtest needs fujinet-pc listening for Bus-over-IP on 127.0.0.1:9995 and the
# track server on EB_SERVER (default http://localhost:8080). MAME must run from
# its own tree or -autoboot_script is silently ignored.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(dirname "$HERE")"
MAME="${MAME:-$HOME/Workspace/mame}"
SCRIPT="${1:-ebtest}"
ROM="${2:-$ROOT/build/excitebike-fujinet.nes}"
[ -x "$MAME/mame" ] || { echo "run-mame.sh: no mame binary in $MAME" >&2; exit 1; }
[ -f "$ROM" ] || { echo "run-mame.sh: no ROM at $ROM (python3 build.py first)" >&2; exit 1; }
ROM="$(realpath "$ROM")"                  # MAME runs from its own tree
export EB_TEST_DIR="$HERE"
SLOT=(-nes_slot fujinet)
[ "$SCRIPT" = nocart ] && SLOT=()          # a plain NROM board: no mailbox at all
OUT="$ROOT/build/$SCRIPT.out"                # full MAME output, for a failure
mkdir -p "$ROOT/build/snap"
cd "$MAME"
./mame nes "${SLOT[@]}" -cart "$ROM" \
     -autoboot_script "$HERE/$SCRIPT.lua" \
     -video none -sound none -nothrottle -seconds_to_run "${SECS:-200}" \
     -snapshot_directory "$ROOT/build/snap" 2>&1 \
  | grep -v 'Average speed' | tee "$OUT" | grep -E '^(PASS|FAIL|fujinet:|sfxdiff:| +[0-9.]+s )' || true
case "$SCRIPT" in
    sfxdiff) grep -q '^sfxdiff:' "$OUT" ;;            # it only writes a log
    *) grep -q '^PASS:' "$OUT" || { echo "--- $OUT ---"; cat "$OUT"; exit 1; } ;;
esac
