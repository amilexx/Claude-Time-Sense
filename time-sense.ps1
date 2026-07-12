# time-sense.ps1 — Claude Code hook script (full version, Windows)
#
# Wired to two hook events:
#   UserPromptSubmit -> time-sense.ps1 received : prints the time context block.
#                                                 On this event a hook's stdout is appended to
#                                                 the model's context for that turn.
#   Stop             -> time-sense.ps1 done     : records end-of-turn, silently.
#
# Env vars:
#   TIME_SENSE_LOG : log path            (default: ~\.claude\time-sense.tsv)
#   TIME_SENSE_GAP : gap threshold, secs (default: 21600 = 6h)

param([string]$Event = "received")

$ErrorActionPreference = "Stop"

$home_dir = if ($env:USERPROFILE) { $env:USERPROFILE } else { $HOME }
$log = if ($env:TIME_SENSE_LOG) { $env:TIME_SENSE_LOG } else { Join-Path $home_dir ".claude\time-sense.tsv" }
$gap = if ($env:TIME_SENSE_GAP) { [int]$env:TIME_SENSE_GAP } else { 21600 }

$dir = Split-Path -Parent $log
if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }

# Hooks deliver JSON on stdin. Only read it if something is actually piped in.
$session = "unknown"
if ([Console]::IsInputRedirected) {
    $raw = [Console]::In.ReadToEnd()
    if ($raw -match '"session_id"\s*:\s*"([^"]*)"') { $session = $Matches[1] }
}

$now      = Get-Date
$nowEpoch = [int][double]::Parse((Get-Date -Date $now.ToUniversalTime() -UFormat %s))
$nowDay   = $now.ToString("yyyy-MM-dd")
$tz       = [System.TimeZoneInfo]::Local.StandardName
$nowHuman = "$($now.ToString('yyyy-MM-dd HH:mm:ss')) $tz ($($now.DayOfWeek))"

$DOCTRINE_FULL  = "Use this for chronological coherence, real durations and deadlines. NEVER comment on the user's sleep, fatigue, energy or the lateness of the hour, and never suggest a break, rest, or picking this up tomorrow - whatever the clock says."
$DOCTRINE_SHORT = "Time is for coherence and deadlines only - never comment on sleep, fatigue or the late hour."

function Format-Delta([int]$s) {
    if ($s -lt 0) { $s = 0 }
    $d = [math]::Floor($s / 86400)
    $h = [math]::Floor(($s % 86400) / 3600)
    $m = [math]::Floor(($s % 3600) / 60)
    $parts = @()
    if ($d -gt 0) { $parts += "${d}d" }
    if ($h -gt 0) { $parts += "${h}h" }
    if ($m -gt 0) { $parts += "${m}m" }
    if ($parts.Count -eq 0) { return "$($s % 60)s" }
    return ($parts -join " ")
}

function Get-LastOf([string]$label) {
    if (-not (Test-Path $log)) { return $null }
    $hit = $null
    foreach ($line in Get-Content $log) {
        $f = $line -split "`t"
        if ($f.Count -ge 4 -and $f[2] -eq $label) { $hit = $f }
    }
    return $hit
}

function Add-Record([string]$label) {
    # AppendAllText with a BOM-less UTF-8 encoder: Out-File -Encoding utf8 on PS 5.1 would
    # stamp a BOM onto the first record, corrupting the epoch in field 0 when it's read back.
    [System.IO.File]::AppendAllText($log, "$nowEpoch`t$nowDay`t$label`t$session`r`n", (New-Object System.Text.UTF8Encoding $false))
}

if ($Event -eq "done") {
    Add-Record "done"
    exit 0
}

# Stateless mode (version A): print the clock and the doctrine, touch nothing.
if ($Event -eq "clock") {
    Write-Output "<time-sense>"
    Write-Output "Real time: $nowHuman"
    Write-Output "Use this for chronological coherence, real durations and deadlines; if it conflicts with earlier timestamps in the transcript, trust the real clock. $DOCTRINE_FULL"
    Write-Output "</time-sense>"
    exit 0
}

# ---- Event = received: build the block that gets injected into context ----
$lines = @("Real time: $nowHuman")
$newSession = $true

$lastDone = Get-LastOf "done"
if ($lastDone) {
    $lastEpoch = [int]$lastDone[0]
    $lastDay   = $lastDone[1]
    if ($lastDone[3] -eq $session) { $newSession = $false }

    $delta = $nowEpoch - $lastEpoch
    if ($delta -gt $gap) {
        $lines += "GAP: $(Format-Delta $delta) since the last exchange (on $lastDay). This is NOT a continuous session - reason about the real timeline, not the apparent continuity of the transcript."
    }
    elseif ($lastDay -ne $nowDay) {
        $lines += "DAY BOUNDARY: the last exchange was on $lastDay, a different calendar day ($(Format-Delta $delta) ago)."
    }
}

# Real duration of the previous turn - worth surfacing after a long build or test run.
$lastRecv = Get-LastOf "received"
if ($lastRecv -and $lastDone) {
    $turn = [int]$lastDone[0] - [int]$lastRecv[0]
    if ($turn -ge 60) { $lines += "Previous turn took $(Format-Delta $turn) of real processing." }
}

# Spell the doctrine out in full once per session; keep it to one line afterwards, so a long
# session doesn't pay for the same paragraph on every single turn.
if ($newSession) { $lines += $DOCTRINE_FULL } else { $lines += $DOCTRINE_SHORT }

Write-Output "<time-sense>"
$lines | ForEach-Object { Write-Output $_ }
Write-Output "</time-sense>"

Add-Record "received"
exit 0
