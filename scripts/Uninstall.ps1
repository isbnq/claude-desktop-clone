<#
.SYNOPSIS
    Removes the desktop shortcuts created by Setup.ps1. Optionally deletes the
    profile data (logins/history) too.

.PARAMETER Profile
    Profile names to remove. Default: Work, Personal.

.PARAMETER InstallDir
    Where the launcher scripts (bin\) were installed. Default:
    %USERPROFILE%\ClaudeProfiles. (Profile *data* lives under %APPDATA%\<name>.)

.PARAMETER RemoveData
    Also delete the isolated profile data directories (this signs you out and
    erases that profile's local history). Only folders that Setup.ps1 created
    (they contain a '.claude-desktop-clone' marker file) are deleted; anything
    else is left alone. %APPDATA%\Claude -- the regular app's login, which a
    -ReuseDefaultForWork "Work" profile shares -- is never deleted.
#>
[CmdletBinding()]
param(
    [string[]]$Profile = @('Work', 'Personal'),
    [string]$InstallDir = (Join-Path $env:USERPROFILE 'ClaudeProfiles'),
    [switch]$RemoveData
)

# Setup.ps1 writes this into every data dir it creates; -RemoveData only deletes
# folders that contain it.
$markerName = '.claude-desktop-clone'

# Same rule as Setup.ps1: plain names only, so %APPDATA%\<name> can never point
# somewhere else (e.g. "..") before it's deleted recursively.
$Profile = @($Profile -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
foreach ($name in $Profile) {
    if ($name -notmatch '^[A-Za-z0-9_-]+( [A-Za-z0-9_-]+)*$') {
        throw "Invalid profile name '$name'. Use only letters, digits, spaces, '-' and '_'."
    }
}

$desktop = [Environment]::GetFolderPath('Desktop')

foreach ($name in $Profile) {
    $lnk = Join-Path $desktop "Claude ($name).lnk"
    if (Test-Path $lnk) {
        Remove-Item $lnk -Force
        Write-Host "Removed shortcut: $lnk" -ForegroundColor Yellow
    }

    if ($RemoveData) {
        # Profile data lives under %APPDATA%\<name> (see Setup.ps1), not -InstallDir.
        $dataDir = Join-Path $env:APPDATA $name
        if ($dataDir -ieq (Join-Path $env:APPDATA 'Claude')) {
            # %APPDATA%\Claude is the main login shared with the Start-menu app.
            Write-Host "Skipping data removal for '$name' (shared main login)." -ForegroundColor DarkYellow
        } elseif (Test-Path (Join-Path $dataDir $markerName)) {
            Remove-Item $dataDir -Recurse -Force
            Write-Host "Removed profile data: $dataDir" -ForegroundColor Yellow
        } elseif (Test-Path $dataDir) {
            Write-Warning "Not removing $dataDir`: it has no '$markerName' marker, so Setup.ps1 didn't create it. If it is a profile from an older Setup.ps1, re-run Setup.ps1 to mark it, or delete it by hand."
        }
    }
}

Write-Host "Done."
