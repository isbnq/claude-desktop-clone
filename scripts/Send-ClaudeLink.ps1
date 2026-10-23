<#
.SYNOPSIS
    Sends a copied claude:// link -- typically the browser's "Open Claude"
    sign-in link -- to one profile's running Claude window.

.DESCRIPTION
    Windows opens claude:// links with the default Claude profile
    (%APPDATA%\Claude), so a profile made by Setup.ps1 never receives the link
    that finishes its browser sign-in: "Open Claude" brings up the main window
    instead, which ignores it (it didn't start that sign-in). Copy the link --
    "Open Claude" is a script button, so take it from the browser's DevTools
    console line "Launched external handler for 'claude://...'" -- and run
    this script. It starts Claude.exe with that profile's --user-data-dir plus
    the link, and the already-running instance picks the link up.

    The link is a one-time sign-in code, so this script never prints it.

.PARAMETER Profile
    The profile name given to Setup.ps1 (its data lives in %APPDATA%\<name>).

.PARAMETER Url
    The claude:// link, alone or inside other text. Default: read it from the
    clipboard.

.EXAMPLE
    .\Send-ClaudeLink.ps1 -Profile Personal
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Profile,

    [string]$Url
)

$ErrorActionPreference = 'Stop'

# Same name rule as Setup.ps1 / Uninstall.ps1.
$Profile = $Profile.Trim()
if ($Profile -notmatch '^[A-Za-z0-9_-]+( [A-Za-z0-9_-]+)*$') {
    throw "Invalid profile name '$Profile'. Use only letters, digits, spaces, '-' and '_'."
}
$dataDir = Join-Path $env:APPDATA $Profile
if (-not (Test-Path $dataDir)) {
    throw "No profile data at $dataDir. Run Setup.ps1 -Profile '$Profile' first."
}

if (-not $Url) { $Url = Get-Clipboard -Raw }
# Take the link on its own or out of surrounding text, e.g. the browser console
# line "Launched external handler for 'claude://...'."
$link = [regex]::Match("$Url", 'claude://[^\s''"<>]+')
if (-not $link.Success) {
    throw "No claude:// link found. Copy the 'Launched external handler for ...' line from the browser's DevTools console (see README), then run this again."
}
$Url = $link.Value

# The link only works in the window that started the sign-in, so that profile
# must already be running. (Starting it fresh from here would also leave out
# its CLAUDE_CONFIG_DIR.) Matches both quoted and unquoted --user-data-dir.
$dirPattern = '--user-data-dir="?' + [regex]::Escape($dataDir) + '"?(\s|$)'
$running = Get-CimInstance Win32_Process -Filter "Name='Claude.exe'" |
    Where-Object { $_.CommandLine -match $dirPattern }
if (-not $running) {
    throw "Claude ($Profile) isn't running. Open it from its shortcut, start the sign-in in that window, then copy the new link and run this again."
}

# Launch-Claude.ps1 reports failures with `exit 1`, which only ends that script.
$global:LASTEXITCODE = 0
& (Join-Path $PSScriptRoot 'Launch-Claude.ps1') -ProfileDir $dataDir -Url $Url
if ($global:LASTEXITCODE) { exit $global:LASTEXITCODE }
Write-Host "Sent the link to Claude ($Profile)." -ForegroundColor Green
