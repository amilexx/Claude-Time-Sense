#!/usr/bin/env bash
#
# time-sense — installer
#
#   bash install.sh status   Report whether time-sense is wired into settings.json.
#                            Exit 0 = installed, exit 1 = not installed.
#   bash install.sh light    Version A — pure context injection.
#                            One inline command in settings.json. No files, no state.
#   bash install.sh full     Version B — version A plus a persistent script.
#                            Adds cold-gap detection across sessions and real turn durations.
#   bash install.sh remove   Cleanly uninstall either version.
#
# The installer MERGES into settings.json: your existing hooks are preserved, and a timestamped
# backup is written before any change.

set -euo pipefail

MODE="${1:-}"
CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
SETTINGS="$CLAUDE_DIR/settings.json"
DEST="$CLAUDE_DIR/time-sense"
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MARK="time-sense"

case "$MODE" in
  status|light|full|remove) ;;
  *) echo "usage: bash install.sh {status|light|full|remove}" >&2; exit 2 ;;
esac

command -v python3 >/dev/null 2>&1 || { echo "python3 is required to merge JSON safely." >&2; exit 2; }

# ---------- status ----------
if [ "$MODE" = "status" ]; then
  if [ ! -f "$SETTINGS" ]; then
    echo "NOT INSTALLED (no settings.json at $SETTINGS)"
    exit 1
  fi
  SETTINGS="$SETTINGS" MARK="$MARK" DEST="$DEST" python3 - <<'PY'
import json, os, sys
path, mark, dest = os.environ["SETTINGS"], os.environ["MARK"], os.environ["DEST"]
try:
    cfg = json.load(open(path))
except Exception:
    print("NOT INSTALLED (settings.json unreadable)"); sys.exit(1)

def ours(event):
    return [h for g in cfg.get("hooks", {}).get(event, [])
              for h in g.get("hooks", [])
              if mark in str(h.get("command", ""))]

submit, stop = ours("UserPromptSubmit"), ours("Stop")
if not submit:
    print("NOT INSTALLED"); sys.exit(1)
if stop and os.path.exists(os.path.join(dest, "time-sense.sh")):
    print("INSTALLED: version B (injection + persistent script)")
else:
    print("INSTALLED: version A (pure injection)")
sys.exit(0)
PY
  exit $?
fi

mkdir -p "$CLAUDE_DIR"
[ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"
cp "$SETTINGS" "$SETTINGS.bak.$(date +%Y%m%d%H%M%S)"

if [ "$MODE" = "full" ]; then
  # Be forgiving about layout: the hook script normally lives in scripts/, but tolerate it
  # sitting next to the installer. Fail loudly rather than half-installing.
  SOURCE=""
  for c in "$SRC/time-sense.sh" "$SRC/scripts/time-sense.sh"; do
    [ -f "$c" ] && { SOURCE="$c"; break; }
  done
  if [ -z "$SOURCE" ]; then
    echo "ERROR: cannot find time-sense.sh." >&2
    echo "Looked in: $SRC/ and $SRC/scripts/" >&2
    echo "The repo is incomplete. Check with:  git ls-files" >&2
    exit 1
  fi
  mkdir -p "$DEST"
  cp "$SOURCE" "$DEST/time-sense.sh"
  chmod +x "$DEST/time-sense.sh" 2>/dev/null || true
  echo "script installed: $DEST/time-sense.sh"
fi

# Version A's inline command: reads the clock and states the doctrine, with zero state.
read -r -d '' LIGHT_CMD <<'EOF' || true
printf "<time-sense>\nReal time: %s\nUse this for chronological coherence, real durations and deadlines; if it conflicts with earlier timestamps in the transcript, trust the real clock. NEVER comment on the user's sleep, fatigue, energy or the lateness of the hour, and never suggest a break, rest, or picking this up tomorrow — whatever the clock says.\n</time-sense>\n" "$(date '+%Y-%m-%d %H:%M:%S %Z (%A)')"
EOF

MODE="$MODE" SETTINGS="$SETTINGS" DEST="$DEST" MARK="$MARK" LIGHT_CMD="$LIGHT_CMD" python3 - <<'PY'
import json, os

mode  = os.environ["MODE"]
path  = os.environ["SETTINGS"]
dest  = os.environ["DEST"]
mark  = os.environ["MARK"]
light = os.environ["LIGHT_CMD"].strip()

try:
    cfg = json.load(open(path))
except json.JSONDecodeError:
    raise SystemExit(f"{path} is not valid JSON — fix it, then re-run.")

hooks = cfg.setdefault("hooks", {})

def strip_ours(event):
    """Remove only OUR entries, leaving third-party hooks untouched."""
    kept = []
    for g in hooks.get(event, []):
        g = dict(g)
        g["hooks"] = [h for h in g.get("hooks", []) if mark not in str(h.get("command", ""))]
        if g["hooks"]:
            kept.append(g)
    if kept:
        hooks[event] = kept
    else:
        hooks.pop(event, None)

for ev in ("UserPromptSubmit", "Stop"):
    strip_ours(ev)

if mode != "remove":
    if mode == "full":
        script = os.path.join(dest, "time-sense.sh")
        submit_cmd = f'bash "{script}" received'
        hooks.setdefault("Stop", []).append(
            {"hooks": [{"type": "command", "command": f'bash "{script}" done', "timeout": 5}]}
        )
    else:
        # The marker must appear in the command so 'remove' and 'status' can recognise it.
        submit_cmd = f"# {mark}\n{light}"

    hooks.setdefault("UserPromptSubmit", []).append(
        {"hooks": [{"type": "command", "command": submit_cmd, "timeout": 10}]}
    )

if not hooks:
    cfg.pop("hooks", None)

with open(path, "w") as f:
    json.dump(cfg, f, indent=2, ensure_ascii=False)
    f.write("\n")

print({"light":  "Version A (pure injection) installed.",
       "full":   "Version B (injection + persistent script) installed.",
       "remove": "time-sense uninstalled."}[mode])
PY

[ "$MODE" = "remove" ] && rm -rf "$DEST"

echo "settings: $SETTINGS  (timestamped .bak written)"
echo
echo "IMPORTANT: Claude Code snapshots hook config at session start."
echo "Restart Claude Code, then run /hooks to confirm time-sense is live."
