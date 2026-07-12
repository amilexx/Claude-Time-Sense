# time-sense

**A sense of real time for Claude Code.**

Claude has no clock. It doesn't know what time it is, or whether two of your messages are five minutes or five days apart — so it guesses from conversational content. That produces two failures:

- **Chronological drift.** A thread resumed the next day reads as one continuous block. Claude says "I just did X" when X was three days ago.
- **Miscalibrated paternalism.** Because fatigue is inferred rather than measured, Claude tells people to go to sleep at 8:30 in the morning. Anthropic has called this a "character tic" pending a model-level fix.

`time-sense` replaces the guess with the actual system clock, and explicitly forbids using it to nanny you.

## How it works

Claude Code fires a `UserPromptSubmit` hook when you submit a prompt, and on that event **the hook's stdout is appended to the model's context**. So the clock gets injected on every message, automatically:

```
<time-sense>
Real time: 2026-07-12 21:14:03 CEST (Sunday)
GAP: 3d since the last exchange (on 2026-07-09). This is NOT a continuous session — reason
about the real timeline, not the apparent continuity of the transcript.
Previous turn took 8m of real processing.
Use this for chronological coherence, real durations and deadlines. NEVER comment on the
user's sleep, fatigue, energy or the lateness of the hour...
</time-sense>
```

This is *context injection* — an intended, documented mechanism, not "prompt injection".

## Install

The skill directory **must** be named `time-sense` (that's the skill's declared name), even though the repo is `Claude-Time-Sense`. Pass the target explicitly — don't let `git clone` pick the name for you.

**macOS / Linux / WSL / Git Bash**

```bash
git clone https://github.com/amilexx/Claude-Time-Sense ~/.claude/skills/time-sense
cd ~/.claude/skills/time-sense
bash install.sh full     # or: light
```

**Native Windows (PowerShell)**

```powershell
git clone https://github.com/amilexx/Claude-Time-Sense "$env:USERPROFILE\.claude\skills\time-sense"
cd "$env:USERPROFILE\.claude\skills\time-sense"
.\install.ps1 full       # or: light
```

Then **restart Claude Code** — hook config is snapshotted at session start. Confirm with `/hooks`.

The installer *merges* into `settings.json`: your existing hooks are preserved, and a timestamped `.bak` is written before any change.

Installed as a skill, it also self-checks: the first time it comes up, Claude runs the installer's `status` command and offers to wire the hooks if they aren't live yet.

### Platform notes

Claude Code on Windows runs **hook commands through Git Bash** (`/usr/bin/bash`), even when your `defaultShell` is `powershell`. That has two consequences the installer handles for you:

- **`powershell` is not on Git Bash's PATH.** A hook that calls a bare `powershell …` dies with `powershell: command not found` and injects nothing. So `install.ps1` registers the **absolute path** to `powershell.exe` with forward slashes — `"C:/WINDOWS/System32/WindowsPowerShell/v1.0/powershell.exe" -File …` — which runs verbatim whether the hook is spawned by Git Bash, cmd, or PowerShell.
- **No BOM in `settings.json`.** Windows PowerShell 5.1's `Out-File -Encoding utf8` prepends a UTF-8 byte-order mark, and Claude Code's JSON parser rejects a leading BOM — silently disabling *every* hook in the file. The installer writes BOM-less UTF-8 instead.

One more Windows detail: version A ships as a small stateless script rather than an inline command, because inline commands with nested quotes behave differently across shells. It still keeps **no state and no log** — that's the real distinction between A and B.

| | `install.sh` | `install.ps1` |
|---|---|---|
| Requires | `bash`, `python3` | PowerShell 5.1+ (built into Windows) |
| Version A footprint | zero files — one inline command | one stateless script, no log |

## Two versions

| | **A — pure injection** (`light`) | **B — injection + script** (`full`) |
|---|---|---|
| Footprint | one inline command in `settings.json` | + `~/.claude/time-sense/` and a TSV log |
| Real clock, every turn | ✅ | ✅ |
| Anti-nanny doctrine | ✅ | ✅ |
| Gaps within a live transcript | ✅ | ✅ |
| Cold gaps (compacted context, fresh session) | ❌ | ✅ |
| Real turn duration | ❌ | ✅ |

**A** is zero-footprint: one `date` call, no files, no state. Timestamps accumulate in the transcript, so Claude can see the gaps itself — until the context is compacted or a new session starts, at which point there's nothing left to compare.

**B** adds a `Stop` hook that records end-of-turn (its stdout isn't injected, so it writes to a log instead of speaking). Turn duration is measured between `received` and `done` and reported on the next turn. State persists across restarts, which is what makes cold-gap detection possible.

They're interchangeable — re-running the installer in the other mode replaces the config cleanly.

## Commands

```bash
bash install.sh status   # is it wired in? (exit 0 = yes)
bash install.sh light    # version A
bash install.sh full     # version B
bash install.sh remove   # clean uninstall (leaves third-party hooks intact)
```

```powershell
.\install.ps1 status     # same four commands on native Windows
.\install.ps1 light
.\install.ps1 full
.\install.ps1 remove
```

## Tuning

| Variable | Default | Meaning |
|---|---|---|
| `TIME_SENSE_LOG` | `~/.claude/time-sense.tsv` | State file (version B) |
| `TIME_SENSE_GAP` | `21600` (6h) | Gap threshold before flagging a discontinuity |

## The rule

The clock is for **coherence and usefulness, not surveillance**. Whatever the hour: no suggesting sleep or breaks, no commenting on fatigue, energy, or how late it is, no unsolicited wellness checks, no winding a session down because it's 3am. If the user raises the subject themselves, answer the question asked — and nothing more.

## Known issues

- **`bash: command not found` on Windows.** Use `.\install.ps1` instead, or run from Git Bash.
- **Nothing appears in context.** A bug has been reported where `UserPromptSubmit` injection doesn't reach the model in the **VSCode extension** while working fine in the CLI. Test in a terminal first.
- **Nothing happens after installing.** Restart Claude Code; hook config is only read at session start.

## License

MIT
