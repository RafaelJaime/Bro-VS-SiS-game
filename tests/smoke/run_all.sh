#!/usr/bin/env bash
# Runs every smoke script in a real (windowed) Godot instance and fails when a
# script exits non-zero or the engine prints a script/parse error.
#
#   GODOT=/path/to/Godot tests/smoke/run_all.sh
#   SHOT_DIR=/some/dir tests/smoke/run_all.sh   # where screenshots go
#   VISIBLE=1 tests/smoke/run_all.sh            # plain windowed run (the window may take focus)
#
# On macOS the windowed scripts run in a private copy of Godot.app whose Info.plist
# marks it LSUIElement (an "accessory" app: no Dock icon, never the frontmost app),
# launched with `open -g -n` so it neither activates nor steals the keyboard focus
# from whatever you are working in. The copy lives in .godot/smoke-app (rebuilt
# when the engine changes). `open` does not report the exit status, so the result
# is read from the SUMMARY / FAIL lines the scripts print. A guard samples the
# frontmost application during the whole run and fails when the smoke engine ever
# becomes it. Click tests are unaffected: every event is injected in-process.
set -u

cd "$(dirname "$0")/../.."
ROOT="$PWD"
GODOT="${GODOT:-$HOME/Library/Application Support/Steam/steamapps/common/Godot Engine/Godot.app/Contents/MacOS/Godot}"
export SHOT_DIR="${SHOT_DIR:-${TMPDIR:-/tmp}/bvs-smoke-shots}"
BG_BUNDLE_ID="org.bvs.godot-smoke"
# Optional "X,Y" the windowed scripts open at. Keep it on a screen: a window
# parked off-screen is occluded and the engine stops presenting frames.
WINDOW_POSITION="${WINDOW_POSITION:-}"
POSITION_ARGS=()
if [ -n "$WINDOW_POSITION" ]; then
	POSITION_ARGS=(--position "$WINDOW_POSITION")
fi

BACKGROUND=0
if [[ "$(uname)" == "Darwin" && "${VISIBLE:-0}" != "1" && "$GODOT" == */Contents/MacOS/* ]]; then
	BACKGROUND=1
fi

# Builds (once per engine build) the accessory copy of Godot.app; echoes its path.
ensure_background_app() {
	local source_app="${GODOT%/Contents/MacOS/*}"
	local target="$ROOT/.godot/smoke-app/Godot.app"
	local stamp="$ROOT/.godot/smoke-app/stamp"
	local want
	want="$(stat -f '%z-%m' "$GODOT")"
	if [[ -x "$target/Contents/MacOS/Godot" && "$(cat "$stamp" 2>/dev/null)" == "$want" ]]; then
		echo "$target"
		return 0
	fi
	rm -rf "$ROOT/.godot/smoke-app"
	mkdir -p "$target/Contents/MacOS"
	# Clone (APFS, instant) when possible, else a plain copy.
	cp -c "$GODOT" "$target/Contents/MacOS/Godot" 2>/dev/null || cp "$GODOT" "$target/Contents/MacOS/Godot"
	[[ -d "$source_app/Contents/Frameworks" ]] && { cp -cR "$source_app/Contents/Frameworks" "$target/Contents/Frameworks" 2>/dev/null || cp -R "$source_app/Contents/Frameworks" "$target/Contents/Frameworks"; }
	[[ -d "$source_app/Contents/Resources" ]] && { cp -cR "$source_app/Contents/Resources" "$target/Contents/Resources" 2>/dev/null || cp -R "$source_app/Contents/Resources" "$target/Contents/Resources"; }
	cp "$source_app/Contents/Info.plist" "$target/Contents/Info.plist"
	plutil -insert LSUIElement -bool true "$target/Contents/Info.plist" 2>/dev/null || plutil -replace LSUIElement -bool true "$target/Contents/Info.plist"
	plutil -replace CFBundleIdentifier -string "$BG_BUNDLE_ID" "$target/Contents/Info.plist"
	plutil -remove CFBundleDocumentTypes "$target/Contents/Info.plist" 2>/dev/null
	codesign --force --deep -s - "$target" >/dev/null 2>&1
	echo "$want" >"$stamp"
	echo "$target"
}

# Bundle id of the frontmost application ("" when unknown).
frontmost_bundle() {
	lsappinfo info -only bundleid "$(lsappinfo front)" 2>/dev/null | sed -e 's/.*=//' -e 's/"//g'
}

failed=0

if [ "$BACKGROUND" -eq 1 ]; then
	BG_APP="$(ensure_background_app)"
	GUARD_DIR="$(mktemp -d)"
	GUARD_LOG="$GUARD_DIR/frontmost.log"
	GUARD_STOP="$GUARD_DIR/stop"
	FRONT_BEFORE="$(frontmost_bundle)"
	tests/smoke/focus_keeper.sh "$BG_BUNDLE_ID" "$GUARD_LOG" "$GUARD_STOP" &
	SAMPLER_PID=$!
fi

# Refresh the imported assets and the global class cache first, so new
# class_names resolve when the scripts run outside the editor.
"$GODOT" --headless --path . --import >/dev/null 2>&1

SCRIPTS=(stage_floor combat movement movement_feel hit_rules hud food_size camera train_loads screenshots cpu_combat cpu_recovery cpu_match cpu_select cpu_shots table_stage hud_framing match_flow match_e2e smash_moves ledge cpu_smash match_reel keyboard_playtest backdrop navigation results_screen visibility hf_picker credits menu_background schema_v2 schema_v3 onnx_golden policy_match policy_select shield shield_spam air_punch attack_timing frame_data shield_look combat_shots food_balance hazards cpu_shield defeat)
# ONLY="hud navigation" tests/smoke/run_all.sh runs just those scripts.
if [ -n "${ONLY:-}" ]; then
	read -r -a SCRIPTS <<<"$ONLY"
fi
# Scripts that simulate minutes of game time and take no screenshots: headless
# runs are not paced to the display, so they finish in seconds.
HEADLESS=" cpu_combat cpu_recovery cpu_match cpu_select hud_framing  match_e2e cpu_smash schema_v2 schema_v3 onnx_golden policy_match shield shield_spam air_punch attack_timing frame_data food_balance hazards cpu_shield "

# Runs one windowed script and prints its combined output. Without the
# background launcher the exit code is the script's; with it, `open` hides the
# status, so a missing SUMMARY or any FAIL / failed count marks the failure.
run_windowed() {
	local name="$1" out err
	if [ "$BACKGROUND" -eq 0 ]; then
		"$GODOT" --path . --resolution 800x600 --fixed-fps 60 --script "res://tests/smoke/${name}.gd" 2>&1
		return $?
	fi
	out="$(mktemp)"
	err="$(mktemp)"
	open -g -n -W --stdout "$out" --stderr "$err" -a "$BG_APP" --args --path "$ROOT" --resolution 800x600 ${POSITION_ARGS[@]+"${POSITION_ARGS[@]}"} --fixed-fps 60 --script "res://tests/smoke/${name}.gd"
	cat "$out" "$err"
	local code=0
	if ! grep -E '^SUMMARY ' "$out" >/dev/null; then
		echo "FAIL ${name}: the script printed no SUMMARY (crashed or never started)"
		code=1
	fi
	if grep -E '^FAIL ' "$out" >/dev/null || grep -E '^SUMMARY [0-9]+ checks, [1-9][0-9]* failed' "$out" >/dev/null; then
		code=1
	fi
	rm -f "$out" "$err"
	return $code
}

for name in "${SCRIPTS[@]}"; do
	echo "=== ${name} ==="
	if [[ "$HEADLESS" == *" ${name} "* ]]; then
		output="$("$GODOT" --headless --path . --fixed-fps 60 --script "res://tests/smoke/${name}.gd" 2>&1)"
	else
		output="$(run_windowed "$name")"
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

if [ "$BACKGROUND" -eq 1 ]; then
	touch "$GUARD_STOP"
	wait "$SAMPLER_PID" 2>/dev/null
	FRONT_AFTER="$(frontmost_bundle)"
	samples="$(grep -c '^sample$' "$GUARD_LOG")"
	taken="$(grep -c '^taken$' "$GUARD_LOG")"
	stuck="$(grep -c '^stuck$' "$GUARD_LOG")"
	longest="$(grep '^returned ' "$GUARD_LOG" | awk '{ if ($2 > m) m = $2 } END { print m + 0 }')"
	echo "=== focus ==="
	# The engine may flash to the front for an instant as its window opens; the
	# watcher hands the front back within MAX_FRONT_MS, and it must never stay.
	MAX_FRONT_MS="${MAX_FRONT_MS:-1500}"
	if [ "$samples" -gt 0 ] && [ "$stuck" -eq 0 ] && [ "$longest" -le "$MAX_FRONT_MS" ] && [ "$FRONT_AFTER" != "$BG_BUNDLE_ID" ] && [ "$FRONT_BEFORE" != "$BG_BUNDLE_ID" ]; then
		echo "PASS focus: the smoke engine took the front $taken time(s), at most ${longest} ms each, and gave it straight back (${samples} polls; before=${FRONT_BEFORE:-?}, after=${FRONT_AFTER:-?})"
	else
		echo "FAIL focus: the smoke engine held the front (${taken} time(s), longest ${longest} ms, stuck=${stuck}, ${samples} polls; before=${FRONT_BEFORE:-?}, after=${FRONT_AFTER:-?})"
		failed=1
	fi
	rm -rf "$GUARD_DIR"
fi

if [ "$failed" -ne 0 ]; then
	echo "SMOKE FAILED"
	exit 1
fi
echo "SMOKE PASSED"
