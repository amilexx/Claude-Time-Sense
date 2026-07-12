# time-sense — installer (Windows)
#
#   .\install.ps1 status   Report whether time-sense is wired into settings.json.
#                          Exit 0 = installed, exit 1 = not installed.
#   .\install.ps1 light    Version A — stateless. Injects the clock, keeps no log.
#   .\install.ps1 full     Version B — adds cold-gap detection and real turn durations.
#   .\install.ps1 remove   Cleanly uninstall.
#
# Merges into settings.json: existing hooks are preserved, and a timestamped backup is written
# before any change. Works on Windows PowerShell 5.1 and PowerShell 7+.

param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("status", "light", "full", "remove")]
    [string]$Mode
)

$ErrorActionPreference = "Stop"

$homeDir   = if ($env:USERPROFILE) { $env:USERPROFILE } else { $HOME }
$claudeDir = if ($env:CLAUDE_CONFIG_DIR) { $env:CLAUDE_CONFIG_DIR } else { Join-Path $homeDir ".claude" }
$settings  = Join-Path $claudeDir "settings.json"
$dest      = Join-Path $claudeDir "time-sense"
$src       = Split-Path -Parent $MyInvocation.MyCommand.Path
$mark      = "time-sense"

# PS 5.1's ConvertFrom-Json yields PSCustomObject, which is painful to mutate.
# Normalise the whole tree to hashtables/arrays first.
function ConvertTo-Hash($o) {
    if ($null -eq $o) { return $null }
    if ($o -is [string] -or $o -is [ValueType]) { return $o }
    if ($o -is [System.Collections.IDictionary]) {
        $h = @{}
        foreach ($k in $o.Keys) { $h[$k] = ConvertTo-Hash $o[$k] }
        return $h
    }
    if ($o -is [System.Collections.IEnumerable]) {
        return @(foreach ($i in $o) { ConvertTo-Hash $i })
    }
    if ($o -is [PSCustomObject]) {
        $h = @{}
        foreach ($p in $o.PSObject.Properties) { $h[$p.Name] = ConvertTo-Hash $p.Value }
        return $h
    }
    return $o
}

function Get-Settings {
    if (-not (Test-Path $settings)) { return @{} }
    $text = Get-Content $settings -Raw
    if ([string]::IsNullOrWhiteSpace($text)) { return @{} }
    try { return ConvertTo-Hash ($text | ConvertFrom-Json) }
    catch { throw "$settings is not valid JSON - fix it, then re-run." }
}

function Get-OurHooks($cfg, $event) {
    if (-not $cfg.ContainsKey("hooks")) { return @() }
    if (-not $cfg["hooks"].ContainsKey($event)) { return @() }
    $found = @()
    foreach ($g in $cfg["hooks"][$event]) {
        foreach ($h in $g["hooks"]) {
            if ("$($h['command'])" -like "*$mark*") { $found += $h }
        }
    }
    return $found
}

# ---------- status ----------
if ($Mode -eq "status") {
    $cfg = Get-Settings
    $submit = Get-OurHooks $cfg "UserPromptSubmit"
    if ($submit.Count -eq 0) { Write-Output "NOT INSTALLED"; exit 1 }
    $stop = Get-OurHooks $cfg "Stop"
    if ($stop.Count -gt 0 -and (Test-Path (Join-Path $dest "time-sense.ps1"))) {
        Write-Output "INSTALLED: version B (injection + persistent state)"
    } else {
        Write-Output "INSTALLED: version A (stateless injection)"
    }
    exit 0
}

if (-not (Test-Path $claudeDir)) { New-Item -ItemType Directory -Path $claudeDir -Force | Out-Null }
if (-not (Test-Path $settings)) { "{}" | Out-File -FilePath $settings -Encoding utf8 }
Copy-Item $settings "$settings.bak.$(Get-Date -Format 'yyyyMMddHHmmss')"

$cfg = Get-Settings
if (-not $cfg.ContainsKey("hooks")) { $cfg["hooks"] = @{} }
$hooks = $cfg["hooks"]

# Strip only OUR entries, leaving third-party hooks untouched.
foreach ($event in @("UserPromptSubmit", "Stop")) {
    if (-not $hooks.ContainsKey($event)) { continue }
    $kept = @()
    foreach ($g in $hooks[$event]) {
        $inner = @(foreach ($h in $g["hooks"]) { if ("$($h['command'])" -notlike "*$mark*") { $h } })
        if ($inner.Count -gt 0) { $kept += @{ hooks = $inner } }
    }
    if ($kept.Count -gt 0) { $hooks[$event] = $kept } else { $hooks.Remove($event) }
}

if ($Mode -ne "remove") {
    # The hook script sits next to this installer. Tolerate a legacy scripts/ layout too,
    # and fail loudly rather than half-installing.
    $candidates = @(
        (Join-Path $src "time-sense.ps1"),
        (Join-Path $src "scripts\time-sense.ps1")
    )
    $source = $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
    if (-not $source) {
        Write-Output "ERROR: cannot find time-sense.ps1."
        Write-Output "Looked in:"
        $candidates | ForEach-Object { Write-Output "  $_" }
        Write-Output ""
        Write-Output "The repo is incomplete. Check with:  git ls-files"
        Write-Output "Expected: time-sense.ps1 next to install.ps1"
        exit 1
    }

    if (-not (Test-Path $dest)) { New-Item -ItemType Directory -Path $dest -Force | Out-Null }
    Copy-Item $source (Join-Path $dest "time-sense.ps1") -Force
    $script = Join-Path $dest "time-sense.ps1"
    Write-Output "script installed: $script"

    # Invoke powershell.exe explicitly with -File. This parses identically whether the hook is
    # spawned by Git Bash, cmd, or PowerShell — unlike an inline command with nested quotes.
    $base = "powershell -NoProfile -ExecutionPolicy Bypass -File `"$script`""
    $verb = if ($Mode -eq "full") { "received" } else { "clock" }

    if (-not $hooks.ContainsKey("UserPromptSubmit")) { $hooks["UserPromptSubmit"] = @() }
    $hooks["UserPromptSubmit"] = @($hooks["UserPromptSubmit"]) + @{
        hooks = @(@{ type = "command"; command = "$base $verb"; timeout = 10 })
    }

    if ($Mode -eq "full") {
        if (-not $hooks.ContainsKey("Stop")) { $hooks["Stop"] = @() }
        $hooks["Stop"] = @($hooks["Stop"]) + @{
            hooks = @(@{ type = "command"; command = "$base done"; timeout = 5 })
        }
    }
}

if ($hooks.Count -eq 0) { $cfg.Remove("hooks") }

($cfg | ConvertTo-Json -Depth 10) | Out-File -FilePath $settings -Encoding utf8

if ($Mode -eq "remove") {
    if (Test-Path $dest) { Remove-Item $dest -Recurse -Force }
    Write-Output "time-sense uninstalled."
} elseif ($Mode -eq "full") {
    Write-Output "Version B (injection + persistent state) installed."
} else {
    Write-Output "Version A (stateless injection) installed."
}

Write-Output "settings: $settings  (timestamped .bak written)"
Write-Output ""
Write-Output "IMPORTANT: Claude Code snapshots hook config at session start."
Write-Output "Restart Claude Code, then run /hooks to confirm time-sense is live."
