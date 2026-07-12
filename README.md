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

```bash
git clone https://github.com/<you>/time-sense ~/.claude/skills/time-sense
cd ~/.claude/skills/time-sense
bash install.sh full     # or: light
```

Then **restart Claude Code** — hook config is snapshotted at session start. Confirm with `/hooks`.

The installer *merges* into `~/.claude/settings.json`: your existing hooks are preserved, and a timestamped `.bak` is written before any change. `python3` is required for the JSON merge.

Installed as a skill, it also self-checks: the first time it comes up, Claude runs `install.sh status` and offers to wire the hooks if they aren't live yet.

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

## Tuning

| Variable | Default | Meaning |
|---|---|---|
| `TIME_SENSE_LOG` | `~/.claude/time-sense.tsv` | State file (version B) |
| `TIME_SENSE_GAP` | `21600` (6h) | Gap threshold before flagging a discontinuity |

## The rule

The clock is for **coherence and usefulness, not surveillance**. Whatever the hour: no suggesting sleep or breaks, no commenting on fatigue, energy, or how late it is, no unsolicited wellness checks, no winding a session down because it's 3am. If the user raises the subject themselves, answer the question asked — and nothing more.

## Known issues

- **Nothing appears in context.** A bug has been reported where `UserPromptSubmit` injection doesn't reach the model in the **VSCode extension** while working fine in the CLI. Test in a terminal first.
- **Nothing happens after installing.** Restart Claude Code; hook config is only read at session start.

## License

MIT
