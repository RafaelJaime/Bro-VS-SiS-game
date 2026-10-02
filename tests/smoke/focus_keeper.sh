#!/usr/bin/env bash
# Focus guard for the windowed smoke scripts (macOS).
#
#   focus_keeper.sh <smoke-bundle-id> <log-file> <stop-file>
#
# Godot activates itself when its window opens (even when launched with
# `open -g`), which would leave the engine as the frontmost app and hide your
# editor or terminal behind it. This watcher polls the frontmost application;
# the moment the smoke engine is it, the previously frontmost app is brought back
# (`open -b`), so the engine holds the front for a fraction of a second at most
# and is never frontmost while a script runs. Events are appended to the log:
#
#   sample                one poll
#   taken                 the smoke engine became frontmost
#   returned <ms>         focus went back to another app after <ms>
#   stuck                 the engine was still frontmost when the watcher stopped
#
# It stops when <stop-file> exists. Keys are never sent anywhere: the only
# action is re-activating the app that had the front.
set -u
BG="$1"
LOG="$2"
STOP="$3"

now_ms() {
	perl -MTime::HiRes=time -e 'printf "%d", time * 1000'
}

prev=""
since=""
while [[ ! -e "$STOP" ]]; do
	front="$(lsappinfo info -only bundleid "$(lsappinfo front)" 2>/dev/null | sed -e 's/.*=//' -e 's/"//g')"
	echo sample >>"$LOG"
	if [[ "$front" == "$BG" ]]; then
		if [[ -z "$since" ]]; then
			since="$(now_ms)"
			echo taken >>"$LOG"
		fi
		if [[ -n "$prev" ]]; then
			open -b "$prev"
			sleep 0.1
		fi
	else
		if [[ -n "$since" ]]; then
			echo "returned $(($(now_ms) - since))" >>"$LOG"
			since=""
		fi
		[[ -n "$front" ]] && prev="$front"
	fi
	sleep 0.02
done
[[ -n "$since" ]] && echo stuck >>"$LOG"
exit 0
