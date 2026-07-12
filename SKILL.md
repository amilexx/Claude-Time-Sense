---
name: time-sense
description: Gives Claude Code a reliable sense of real time by injecting the system clock into context on every message via a UserPromptSubmit hook. Anchors dates and deadlines, measures how long tasks really took, and detects that a session spread over several days is NOT a few continuous hours. Use this skill to install, configure, or troubleshoot time-sense, and whenever anything touches time, duration, dates, deadlines, or session continuity. Never use the clock to comment on the user's sleep, fatigue, or energy.
---

# time-sense — a sense of real time for Claude Code

## The problem

Claude has no clock. It doesn't know what time it is, or whether two messages are five minutes or five days apart. So it **guesses** from conversational content. Two failure modes follow:

1. **Undetectable chronological drift.** A thread resumed the next day, or spread across a week, reads as one continuous block. Claude reasons on a false timeline: "I just did X" when X was three days ago.
2. **Miscalibrated paternalism.** Because fatigue is inferred rather than measured, Claude ends up telling people to go to sleep at 8:30 in the morning. Anthropic has acknowledged this as a "character tic" pending a model-level fix; an explicit instruction neutralises it in the meantime.

The fix: replace the guess with **real data**, and explicitly forbid using that data to nanny the user.

## The mechanism: context injection

Claude Code fires a `UserPromptSubmit` hook when the user submits a prompt, before Claude processes it — and on that event, **the hook's stdout is appended to the model's context**. The platform injects the clock on every message, with no need for Claude to remember to ask.

This is *context injection*, an intended, documented mechanism — not "prompt injection", a term reserved for attacks.

---

## First run: check that the hooks are actually live

**Reading this file does nothing on its own.** The value lives in a `UserPromptSubmit` hook — the skill is just this guidance. The hook fires automatically on every message; it is never model-invoked. So the only thing to verify is that the hook is wired in.

**Fastest check — look at your own context.** If a `<time-sense>` block is already appearing on the user's messages, the hook is live. Nothing to do. Carry on with the user's actual task. (This is the normal state when time-sense is installed as a **plugin**: Claude Code manages the hook itself, and running any `install.*` script would only add a *second*, duplicate hook — don't.)

Only if **no** block is showing up, and time-sense is installed **standalone** (cloned into `~/.claude/skills/`, not via `/plugin install`), fall back to the installer. It sits in this skill's own directory, next to this `SKILL.md` — nothing to download.

```bash
bash <this-skill-dir>/install.sh status              # macOS, Linux, WSL, Git Bash
```
```powershell
powershell -File <this-skill-dir>\install.ps1 status  # native Windows
```

On Windows, Claude Code's Bash tool *is* Git Bash, where a bare `powershell` is off PATH — if `status` fails with `powershell: command not found`, call it by absolute path instead:

```bash
"$SYSTEMROOT/System32/WindowsPowerShell/v1.0/powershell.exe" -File <this-skill-dir>/install.ps1 status
```

- **Prints `INSTALLED: version A` or `version B`** → nothing to do.
- **Prints `NOT INSTALLED`** → offer to set it up. Ask which version (see the table below), run the installer with `light` or `full`, then tell the user to **restart Claude Code** — hook config is snapshotted at session start, so it won't take effect until then.

Ask before installing rather than doing it silently: writing to `settings.json` is a change to the user's configuration, and they should choose A or B knowingly. It's one short question, not an obstacle.

---

## The two versions

| | **A — pure injection** | **B — injection + script** |
|---|---|---|
| Install | `bash install.sh light` | `bash install.sh full` |
| Footprint | one inline command in `settings.json` | + `~/.claude/time-sense/` and a TSV log |
| Real clock, every turn | yes | yes |
| Anti-nanny doctrine | yes | yes |
| Gaps within a live transcript | yes (Claude compares injected timestamps) | yes |
| **Cold gaps** (compacted context, fresh session) | no | **yes** |
| **Real turn duration** (that 8-minute build) | no | **yes** |

**Version A** injects a block like this on every message:

```
<time-sense>
Real time: 2026-07-12 21:14:03 CEST (Sunday)
Use this for chronological coherence, real durations and deadlines; if it conflicts with
earlier timestamps in the transcript, trust the real clock. NEVER comment on the user's
sleep, fatigue, energy or the lateness of the hour...
</time-sense>
```

Because the block lands on *every* turn, timestamps accumulate in the transcript and Claude can see for itself that three days passed. What A can't do: once the context is compacted or a fresh session starts on an old project, those timestamps are gone and there's nothing left to compare against.

**Version B** adds persistent state and wires a second hook:

| Event | Call | Role |
|---|---|---|
| `UserPromptSubmit` | `time-sense.sh received` | Prints the context block (injected), records arrival |
| `Stop` | `time-sense.sh done` | Records end-of-turn, silently |

`Stop` injects nothing — its stdout doesn't reach context. It **records**. Real turn duration is measured between `received` and `done` and reported on the *next* turn. State lives in `~/.claude/time-sense.tsv`, which survives restarts — that's what makes cold-gap detection work.

```
<time-sense>
Real time: 2026-07-12 21:14:03 CEST (Sunday)
GAP: 3d since the last exchange (on 2026-07-09). This is NOT a continuous session — reason
about the real timeline, not the apparent continuity of the transcript.
Previous turn took 8m of real processing.
[doctrine]
</time-sense>
```

The full doctrine is spelled out once per session and compacted to a single line thereafter, so a long session doesn't pay for the same paragraph on every turn.

**Tuning** (environment variables): `TIME_SENSE_LOG` (log path, default `~/.claude/time-sense.tsv`) and `TIME_SENSE_GAP` (gap threshold in seconds, default `21600` = 6h).

Both versions are interchangeable — re-running `install.sh` in the other mode cleanly replaces the previous config. `bash install.sh remove` uninstalls everything.

---

## The non-negotiable rule

This skill provides the clock **for coherence and usefulness, not to monitor the user**. Knowing the exact time justifies no commentary whatsoever on how they live.

Forbidden, whatever the clock says:

- Suggesting sleep, rest, a break, or picking things up tomorrow.
- Commenting on fatigue, energy, the lateness of the hour, or session length.
- Unprompted reminders to hydrate, eat, or stretch — any unsolicited wellness check.
- Slowing down, shortening, or winding up a session because it's late or it's been long.

It's 3am and the session has run six hours? Continue exactly as if it were 3pm. The topic only comes up if **the user raises it themselves** ("how long until 9am tomorrow?") — and then you answer the question asked, without appending an admonition.

If you find yourself about to mention sleep, fatigue, or the late hour: that is precisely the reflex to suppress.

## What real time makes possible

- **Deadlines** — "due tomorrow" resolves to a concrete date computed from now.
- **Honest continuity** — resume a thread without pretending it's fresh, or forgetting what happened in between.
- **Measured durations** — tell an instant task apart from one that genuinely took 20 minutes.
- **Calendar awareness** — weekday vs weekend, end of month, when it actually bears on the advice.
- **Contextual resumption** — after a gap, a brief re-anchor ("picking up Tuesday's Ubuntu setup") instead of assuming continuity.

## Troubleshooting

The installer **merges** into `~/.claude/settings.json`: existing hooks are preserved and a timestamped `.bak` is written before every change. `python3` is required for the JSON merge.

**Block not showing up in context?** A bug has been reported where `UserPromptSubmit` injection didn't reach the model in the VSCode extension while working fine in the CLI — test in a terminal first. Also note this event has a short default timeout (30s); on timeout the output is discarded and the prompt proceeds without context. Not a concern here — the script runs in milliseconds.

**Nothing happens after install.** Restart Claude Code. Hook config is snapshotted at session start. Confirm with `/hooks`.
