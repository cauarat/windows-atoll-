#!/usr/bin/env bash
# Puts scripts/check-crashes.sh in front of the agent without it having to
# remember. Wired to SessionStart and Stop in .claude/settings.json.
#
# SessionStart answers "has it been falling over?" before any work starts.
# Stop catches what fell over during the session — which is the case that keeps
# happening: a build goes out, the app dies minutes later, and the session ends
# saying the change works.
#
# Reports each distinct crash once per session. Told twice, an agent that is
# blocked from stopping would be blocked again by the same news, and a Stop
# hook that always exits 2 is a session that cannot end.
#
# Usage: crash-hook.sh <SessionStart|Stop>   (hook JSON on stdin)
set -uo pipefail
cd "$(dirname "$0")/.."

EVENT="${1:-Stop}"
INPUT="$(cat 2>/dev/null || true)"
SESSION="$(printf '%s' "$INPUT" | python3 -I -c \
    'import json,sys
try: print(json.load(sys.stdin).get("session_id","nosession"))
except Exception: print("nosession")' 2>/dev/null || echo nosession)"

REPORT="$(bash scripts/check-crashes.sh 2>&1)"
STATUS=$?

# Exit 0 from the reader means nothing new since the installed build. Silence
# is right then: a hook that speaks on every turn gets tuned out.
[ "$STATUS" -eq 0 ] && exit 0

# One marker per session per distinct report. The report text changes when a
# new crash lands, so a second, different crash still gets through.
STATE="${TMPDIR:-/tmp}/coucou-crash-hook-$SESSION"
mkdir -p "$STATE" 2>/dev/null || true
SEEN="$STATE/$(printf '%s' "$REPORT" | shasum | cut -c1-16)"
[ -e "$SEEN" ] && exit 0
: > "$SEEN" 2>/dev/null || true

NOTE="Notchy has crashed since the build that is installed.

$REPORT

Read the report in ~/Library/Logs/DiagnosticReports/ before saying anything
works. A @MainActor closure handed to a background queue is the one that has
done this before; scripts/test-mainactor-dispatch.sh catches that shape."

if [ "$EVENT" = "SessionStart" ]; then
    # Context, not an interruption: at session start there is no work to stop.
    python3 -I -c 'import json,sys; print(json.dumps({
        "hookSpecificOutput": {"hookEventName": "SessionStart",
                               "additionalContext": sys.stdin.read()}}))' <<< "$NOTE"
    exit 0
fi

# Stop: exit 2 puts stderr in front of the agent and keeps the turn open.
echo "$NOTE" >&2
exit 2
