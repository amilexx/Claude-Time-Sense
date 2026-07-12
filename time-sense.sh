#!/usr/bin/env bash
#
# time-sense.sh — Claude Code hook script (full version)
#
# Wired to two hook events:
#   UserPromptSubmit -> time-sense.sh received : prints the time context block.
#                                                On this event, a hook's stdout is appended
#                                                to the model's context for that turn.
#   Stop             -> time-sense.sh done     : records end-of-turn, silently.
#                                                Stop's stdout is NOT injected, so it writes
#                                                to the log instead of speaking.
#
# Real turn duration is therefore measured between 'received' and 'done', and reported on the
# NEXT turn — that's how "the previous build actually took 8 min" becomes knowable.
#
# State lives in a TSV that survives Claude Code restarts. That's what makes cold-gap
# detection possible: a session resumed three days later is not a continuous session.
#
# Env vars:
#   TIME_SENSE_LOG : log path            (default: ~/.claude/time-sense.tsv)
#   TIME_SENSE_GAP : gap threshold, secs (default: 21600 = 6h)

set -uo pipefail

EVENT="${1:-received}"
LOG="${TIME_SENSE_LOG:-$HOME/.claude/time-sense.tsv}"
GAP="${TIME_SENSE_GAP:-21600}"
mkdir -p "$(dirname "$LOG")" 2>/dev/null

# Hooks receive JSON on stdin. Read it without depending on jq, and never block waiting.
raw=""
if [ ! -t 0 ]; then
  # `timeout` is GNU coreutils and absent on stock macOS; fall back to a plain read there.
  # Claude Code closes stdin after sending the hook JSON, so `cat` returns at EOF on its own —
  # the timeout is only a defensive guard against a stray open pipe.
  if command -v timeout >/dev/null 2>&1; then
    raw=$(timeout 1 cat 2>/dev/null || true)
  else
    raw=$(cat 2>/dev/null || true)
  fi
fi
session=$(printf '%s' "$raw" | sed -n 's/.*"session_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
[ -z "$session" ] && session="unknown"

now_epoch=$(date +%s)
now_day=$(date '+%Y-%m-%d')
# %Z (zone abbreviation) comes out as blank whitespace under Git Bash/MSYS on Windows — not an
# empty string — so test for a non-space char and fall back to the numeric offset (%z, +0200).
now_tz=$(date '+%Z')
printf '%s' "$now_tz" | grep -q '[^[:space:]]' || now_tz=$(date '+%z')
now_human=$(date "+%Y-%m-%d %H:%M:%S${now_tz:+ $now_tz} (%A)")

DOCTRINE_FULL="Use this for chronological coherence, real durations and deadlines. NEVER comment on the user's sleep, fatigue, energy or the lateness of the hour, and never suggest a break, rest, or picking this up tomorrow — whatever the clock says."
DOCTRINE_SHORT="Time is for coherence and deadlines only — never comment on sleep, fatigue or the late hour."

fmt() {  # seconds -> "3d 2h 14m" / "45s"
  local s=$1 d h m
  [ "$s" -lt 0 ] && s=0
  d=$(( s / 86400 )); h=$(( (s % 86400) / 3600 )); m=$(( (s % 3600) / 60 ))
  local out=""
  [ "$d" -gt 0 ] && out="${out}${d}d "
  [ "$h" -gt 0 ] && out="${out}${h}h "
  [ "$m" -gt 0 ] && out="${out}${m}m "
  [ "$d" -eq 0 ] && [ "$h" -eq 0 ] && [ "$m" -eq 0 ] && out="$(( s % 60 ))s"
  printf '%s' "${out% }"
}

last_of() {  # last line with label $1  ->  "epoch<TAB>day<TAB>session"
  [ -s "$LOG" ] || return 1
  awk -F'\t' -v want="$1" '$3 == want { e=$1; d=$2; s=$4 } END { if (e) print e "\t" d "\t" s }' "$LOG"
}

record() { printf '%s\t%s\t%s\t%s\n' "$now_epoch" "$now_day" "$1" "$session" >> "$LOG"; }

if [ "$EVENT" = "done" ]; then
  record done
  exit 0
fi

# ---- EVENT = received: build the block that gets injected into context ----
lines=("Real time: $now_human")
new_session=1

if last=$(last_of done); then
  IFS=$'\t' read -r last_epoch last_day last_session <<< "$last"
  [ "$last_session" = "$session" ] && new_session=0

  if [ -n "$last_epoch" ]; then
    delta=$(( now_epoch - last_epoch ))
    if [ "$delta" -gt "$GAP" ]; then
      lines+=("GAP: $(fmt "$delta") since the last exchange (on $last_day). This is NOT a continuous session — reason about the real timeline, not the apparent continuity of the transcript.")
    elif [ "$last_day" != "$now_day" ]; then
      lines+=("DAY BOUNDARY: the last exchange was on $last_day, a different calendar day ($(fmt "$delta") ago).")
    fi
  fi
fi

# Real duration of the previous turn — worth surfacing after a long build or test run.
if last_recv=$(last_of received) && last_done=$(last_of done); then
  r=${last_recv%%$'\t'*}; d=${last_done%%$'\t'*}
  if [ -n "$r" ] && [ -n "$d" ] && [ "$d" -gt "$r" ]; then
    turn=$(( d - r ))
    [ "$turn" -ge 60 ] && lines+=("Previous turn took $(fmt "$turn") of real processing.")
  fi
fi

# Spell the doctrine out in full once per session; keep it to one line afterwards, so a long
# session doesn't pay for the same paragraph on every single turn.
if [ "$new_session" -eq 1 ]; then
  lines+=("$DOCTRINE_FULL")
else
  lines+=("$DOCTRINE_SHORT")
fi

printf '<time-sense>\n'
printf '%s\n' "${lines[@]}"
printf '</time-sense>\n'

record received
exit 0
