#!/usr/bin/env bash
# Runs every smoke script in a real (windowed) Godot instance and fails when a
# script exits non-zero or the engine prints a script/parse error.
#
#   GODOT=/path/to/Godot tests/smoke/run_all.sh
#   SHOT_DIR=/some/dir tests/smoke/run_all.sh   # where screenshots go
set -u

cd "$(dirname "$0")/../.."
GODOT="${GODOT:-$HOME/Library/Application Support/Steam/steamapps/common/Godot Engine/Godot.app/Contents/MacOS/Godot}"
export SHOT_DIR="${SHOT_DIR:-${TMPDIR:-/tmp}/bvs-smoke-shots}"

# Refresh the imported assets and the global class cache first, so new
# class_names resolve when the scripts run outside the editor.
"$GODOT" --headless --path . --import >/dev/null 2>&1

SCRIPTS=(stage_floor combat movement movement_feel hit_rules hud food_size camera train_loads screenshots cpu_combat cpu_recovery cpu_match cpu_select cpu_shots table_stage hud_framing match_flow match_e2e)
# Scripts that simulate minutes of game time and take no screenshots: headless
# runs are not paced to the display, so they finish in seconds.
HEADLESS=" cpu_combat cpu_recovery cpu_match cpu_select hud_framing  match_e2e "
failed=0

for name in "${SCRIPTS[@]}"; do
	echo "=== ${name} ==="
	if [[ "$HEADLESS" == *" ${name} "* ]]; then
		output="$("$GODOT" --headless --path . --fixed-fps 60 --script "res://tests/smoke/${name}.gd" 2>&1)"
	else
		output="$("$GODOT" --path . --resolution 800x600 --fixed-fps 60 --script "res://tests/smoke/${name}.gd" 2>&1)"
	fi
	code=$?
	echo "$output" | grep -E '^(PASS|FAIL|SHOT|SUMMARY|INFO)'
	if echo "$output" | grep -E 'SCRIPT ERROR|Parse Error|Failed to load script' >/dev/null; then
		echo "FAIL ${name}: engine reported script errors"
		echo "$output" | grep -E -B1 -A3 'SCRIPT ERROR|Parse Error|Failed to load script' | head -40
		code=1
	fi
	if [ "$code" -ne 0 ]; then
		echo "RESULT ${name}: FAILED (exit ${code})"
		failed=1
	else
		echo "RESULT ${name}: OK"
	fi
done

if [ "$failed" -ne 0 ]; then
	echo "SMOKE FAILED"
	exit 1
fi
echo "SMOKE PASSED"
