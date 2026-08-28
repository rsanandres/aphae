#!/usr/bin/env bash
# Run the full headless test suite the way CI does — usable locally too.
#
#   GODOT=/path/to/godot tools/run_tests.sh          # everything
#   GODOT=... tools/run_tests.sh goals_test          # one harness
#
# Hard-won rules this script encodes (see PLAN.md "Gotchas"):
#   - The parse check's EXIT CODE is not a gate: godot -e --quit-after 5
#     returned 0 while three scripts failed to compile. Grep the output.
#   - A broken build makes every harness print "0 passed, 0 failed", which a
#     naive grep reads as success. Require passed > 0 AND failed == 0, and
#     treat the harnesses' own "NO ASSERTIONS RAN" guard as fatal.
#   - A runtime error inside an awaited coroutine hangs a harness silently —
#     so every run gets a timeout, and a timeout is a failure.
set -u

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GODOT="${GODOT:-godot}"
TIMEOUT_SECS="${TIMEOUT_SECS:-600}"
HARNESSES=(producer_test confessional_test events_test economy_test goals_test secrets_test)
if [ $# -gt 0 ]; then
	HARNESSES=("$@")
fi

fail=0
say() { printf '%s\n' "$*"; }

# Fresh clones have no .godot import cache; running a scene before the
# filesystem is imported yields missing-resource errors.
say "== import =="
"$GODOT" --headless --path "$REPO" --audio-driver Dummy --import >/dev/null 2>&1

say "== parse check (grep-gated, exit code is a liar) =="
parse_out="$("$GODOT" --headless --path "$REPO" --audio-driver Dummy -e --quit-after 5 2>&1)"
parse_errors="$(printf '%s' "$parse_out" | grep -cE 'Parse Error|Compile Error|Failed to load script')"
if [ "$parse_errors" -ne 0 ]; then
	say "PARSE: FAIL ($parse_errors compile errors)"
	printf '%s\n' "$parse_out" | grep -E 'Parse Error|Compile Error|Failed to load script' | head -20
	fail=1
else
	say "PARSE: OK"
fi

for harness in "${HARNESSES[@]}"; do
	say ""
	say "== $harness =="
	out="$(timeout "$TIMEOUT_SECS" "$GODOT" --headless --path "$REPO" --audio-driver Dummy \
		"res://scenes/main/$harness.tscn" 2>&1)"
	status=$?
	summary="$(printf '%s' "$out" | grep -oE '[0-9]+ passed, [0-9]+ failed' | tail -1)"
	passed="$(printf '%s' "$summary" | grep -oE '^[0-9]+')"
	failed="$(printf '%s' "$summary" | grep -oE '[0-9]+ failed' | grep -oE '[0-9]+')"

	if [ $status -eq 124 ]; then
		say "$harness: FAIL (timed out after ${TIMEOUT_SECS}s — suspect an error inside an awaited coroutine)"
		printf '%s\n' "$out" | tail -15
		fail=1
	elif printf '%s' "$out" | grep -q "NO ASSERTIONS RAN"; then
		say "$harness: FAIL (no assertions ran — the build is broken upstream of the test)"
		fail=1
	elif [ -z "$summary" ] || [ -z "$passed" ] || [ "${passed:-0}" -eq 0 ]; then
		say "$harness: FAIL (no result line — harness never reported)"
		printf '%s\n' "$out" | tail -15
		fail=1
	elif [ "${failed:-1}" -ne 0 ]; then
		say "$harness: FAIL ($summary)"
		printf '%s\n' "$out" | grep -E '^  FAIL' | head -10
		fail=1
	elif printf '%s' "$out" | grep -q "SCRIPT ERROR"; then
		# Assertions can all pass while a runtime error fired somewhere the
		# harness does not assert on. Keep the backtrace, not just the line.
		say "$harness: FAIL ($summary, but SCRIPT ERROR in output)"
		printf '%s\n' "$out" | grep -A6 "SCRIPT ERROR" | head -20
		fail=1
	else
		say "$harness: OK ($summary)"
	fi
done

say ""
if [ $fail -ne 0 ]; then
	say "RESULT: FAIL"
else
	say "RESULT: OK"
fi
exit $fail
