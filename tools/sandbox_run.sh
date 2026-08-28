#!/usr/bin/env bash
# Run Aphae in an isolated, invisible sandbox.
#
# Two problems this solves:
#   1. Visual harnesses (gui_check, panel_check, screenshots) CANNOT run
#      --headless: that swaps in the dummy display driver and every capture
#      comes out blank. They need a real window.
#   2. A real window steals the screen, and the game's user:// data (saves,
#      settings, achievements, producer.json) is shared with whatever the
#      owner is actually playing.
#
# So: mirror the repo into a scratch copy, rename the project (Godot derives
# user:// from config/name, so the rename is what buys the isolation), and
# park the window far off-screen where it still renders but nobody sees it.
#
# Usage:
#   tools/sandbox_run.sh res://scenes/main/panel_check.tscn
#   tools/sandbox_run.sh -s /abs/path/to/probe.gd
#   SANDBOX_KEEP=1 tools/sandbox_run.sh ...   # keep the sandbox for poking at
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SANDBOX="${SANDBOX_DIR:-/tmp/aphae-sandbox}"

# The fallback copy path below does `rm -rf "$SANDBOX"`. Refuse locations
# where a mistyped SANDBOX_DIR would be catastrophic.
case "$SANDBOX" in
	""|"/"|"$HOME"|"$HOME/"|/c|/c/|/d|/d/|/tmp|/tmp/)
		echo "refusing to use '$SANDBOX' as the sandbox dir" >&2
		exit 2
		;;
esac
SANDBOX_NAME="AphaeSandbox"
GODOT="${GODOT:-godot}"

if [ $# -eq 0 ]; then
	echo "usage: $(basename "$0") <res://scene.tscn | -s /path/probe.gd> [extra godot args...]" >&2
	exit 2
fi

mkdir -p "$SANDBOX"
# .git is the bulk of the repo and irrelevant here; .godot is a rebuildable
# import cache that must NOT be shared (it embeds absolute paths).
#
# rsync is absent on some boxes — Git Bash on Windows ships without it — so
# fall back to wipe-and-copy. Same result, just slower.
if command -v rsync >/dev/null 2>&1; then
	rsync -a --delete \
		--exclude '.git/' \
		--exclude '.godot/' \
		"$REPO"/ "$SANDBOX"/
else
	rm -rf "$SANDBOX"
	mkdir -p "$SANDBOX"
	shopt -s dotglob nullglob
	for entry in "$REPO"/*; do
		case "$(basename "$entry")" in
			.git|.godot) continue ;;
		esac
		cp -a "$entry" "$SANDBOX"/
	done
	shopt -u dotglob nullglob
fi

# The rename is the isolation: user:// becomes .../app_userdata/AphaeSandbox,
# so nothing here can touch the real game's saves or lifetime progression.
if [[ "$OSTYPE" == "darwin"* ]]; then
	sed -i '' "s/^config\/name=.*/config\/name=\"$SANDBOX_NAME\"/" "$SANDBOX/project.godot"
else
	sed -i "s/^config\/name=.*/config\/name=\"$SANDBOX_NAME\"/" "$SANDBOX/project.godot"
fi

echo "[sandbox] $SANDBOX (project '$SANDBOX_NAME')"
echo "[sandbox] user data: <Godot app_userdata>/$SANDBOX_NAME"
echo "[sandbox]   macOS:   ~/Library/Application Support/Godot/app_userdata/$SANDBOX_NAME"
echo "[sandbox]   Windows: %APPDATA%/Godot/app_userdata/$SANDBOX_NAME"

# Import pass: a fresh copy has no .godot cache, and running a scene before
# the filesystem is scanned yields missing-resource errors.
"$GODOT" --headless --path "$SANDBOX" --audio-driver Dummy --import >/dev/null 2>&1 || true

# --position parks the window off-screen; it still renders (verified), so
# captures are real while nothing appears on the owner's display.
# --audio-driver Dummy is the repo's standing rule for test runs.
"$GODOT" --path "$SANDBOX" \
	--audio-driver Dummy \
	--position -5000,-5000 \
	"$@"
STATUS=$?

if [ "${SANDBOX_KEEP:-0}" != "1" ]; then
	echo "[sandbox] done (set SANDBOX_KEEP=1 to preserve the copy)"
fi
exit $STATUS
