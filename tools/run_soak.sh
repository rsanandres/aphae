#!/usr/bin/env bash
# The soak: a seeded, bounded, heuristic-only run of the simulation that
# ends in a report (scripts/utils/soak_report.gd) instead of a Ctrl+C.
#
#   GODOT=/path/to/godot tools/run_soak.sh
#
# It does two things, in this order:
#
#   1. Replay check. The same seed is run twice for REPLAY_DAYS game-days;
#      the two fingerprints must match. A mismatch means something in the
#      simulation draws on the wall clock or on iteration order, and a
#      flake can no longer be replayed from its seed.
#   2. The measured run. DAYS game-days, report written to REPORT, and the
#      run fails if repeat_rate is above MAX_REPEAT_RATE.
#
# MAX_REPEAT_RATE is a ratchet, not a target. The target is zero
# (docs/ROADMAP.md). The ceiling sits just above today's measured figure so
# the number cannot get worse unnoticed; lower it every time the voice
# pipeline lands a cut.
#
# Environment:
#   GODOT            engine binary (default: godot)
#   SEED             default 1
#   AGENTS           default 10
#   SPEED            default 1 (the pace a player watches at)
#   DAYS             default 5 (two real hours of play at 1x)
#   REPLAY_DAYS      default 1; 0 skips the replay check
#   MAX_REPEAT_RATE  default 0.70; empty disables the gate
#   REPORT           default build/soak/report.json
set -u

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GODOT="${GODOT:-godot}"
SEED="${SEED:-1}"
AGENTS="${AGENTS:-10}"
SPEED="${SPEED:-1}"
DAYS="${DAYS:-5}"
REPLAY_DAYS="${REPLAY_DAYS:-1}"
MAX_REPEAT_RATE="${MAX_REPEAT_RATE-0.70}"
REPORT="${REPORT:-$REPO/build/soak/report.json}"
TIMEOUT_SECS="${TIMEOUT_SECS:-1200}"

say() { printf '%s\n' "$*"; }
mkdir -p "$(dirname "$REPORT")"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# run <days> <report> <log> [extra sim args...]
run() {
	local days="$1" report="$2" log="$3"
	shift 3
	timeout "$TIMEOUT_SECS" "$GODOT" --headless --path "$REPO" --audio-driver Dummy \
		--fixed-fps 60 res://scenes/main/headless_sim.tscn -- \
		--seed="$SEED" --agents="$AGENTS" --speed="$SPEED" --days="$days" \
		--heuristic --report="$report" "$@" >"$log" 2>&1
}

# A run only counts if it reported and raised no script error.
check() {
	local status="$1" log="$2" label="$3"
	if [ "$status" -eq 124 ]; then
		say "$label: FAIL (timed out after ${TIMEOUT_SECS}s)"
		tail -15 "$log"
		return 1
	fi
	if grep -q "SCRIPT ERROR" "$log"; then
		say "$label: FAIL (SCRIPT ERROR in output)"
		grep -A6 "SCRIPT ERROR" "$log" | head -20
		return 1
	fi
	if ! grep -q "=== SOAK REPORT ===" "$log"; then
		say "$label: FAIL (the run never reported)"
		tail -15 "$log"
		return 1
	fi
	return 0
}

fingerprint() { grep -oE 'fingerprint +[0-9a-f]{64}' "$1" | grep -oE '[0-9a-f]{64}' | tail -1; }

say "== import =="
"$GODOT" --headless --path "$REPO" --audio-driver Dummy --import >/dev/null 2>&1

fail=0

if [ "$REPLAY_DAYS" != "0" ]; then
	say "== replay check: seed $SEED, $REPLAY_DAYS game-day(s), twice =="
	run "$REPLAY_DAYS" "$work/a.json" "$work/a.log"; check $? "$work/a.log" "replay run 1" || fail=1
	run "$REPLAY_DAYS" "$work/b.json" "$work/b.log"; check $? "$work/b.log" "replay run 2" || fail=1
	fa="$(fingerprint "$work/a.log")"
	fb="$(fingerprint "$work/b.log")"
	if [ -z "$fa" ] || [ "$fa" != "$fb" ]; then
		say "REPLAY: FAIL (same seed, different runs)"
		say "  run 1: ${fa:-none}"
		say "  run 2: ${fb:-none}"
		say "  first lines that differ:"
		diff <(grep -v 'written to' "$work/a.log") <(grep -v 'written to' "$work/b.log") | head -12
		fail=1
	else
		say "REPLAY: OK ($fa)"
	fi
fi

say ""
say "== soak: seed $SEED, $AGENTS agents, ${SPEED}x, $DAYS game-day(s) =="
gate=()
if [ -n "$MAX_REPEAT_RATE" ]; then
	gate=(--max-repeat-rate="$MAX_REPEAT_RATE")
fi
run "$DAYS" "$REPORT" "$work/soak.log" "${gate[@]}"
status=$?
if check "$status" "$work/soak.log" "soak"; then
	sed -n '/=== SOAK REPORT ===/,$p' "$work/soak.log" | grep -v 'ObjectDB\|at: cleanup'
	[ "$status" -ne 0 ] && fail=1
else
	fail=1
fi

say ""
if [ $fail -ne 0 ]; then
	say "RESULT: FAIL"
else
	say "RESULT: OK"
fi
exit $fail
