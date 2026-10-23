<#
.SYNOPSIS
    Launches the Claude Desktop (Windows MSIX) app with an isolated profile.

.DESCRIPTION
    The Claude Desktop app is built on Electron/Chromium, which accepts the
    standard `--user-data-dir` flag. Each distinct data directory gets its own
    Chromium "singleton" lock, so multiple instances — each signed into a
    different account — can run side by side.

    This script resolves the MSIX executable dynamically via Get-AppxPackage so
    it keeps working after the app updates (the WindowsApps path contains a
    version number that changes on every update).

.PARAMETER ProfileDir
    Absolute path to the data directory for this instance. A fresh directory =
    a fresh, isolated login. Point it at "$env:APPDATA\Claude" to reuse the
    account that the normally-installed app is already signed into.

.EXAMPLE
    .\Launch-Claude.ps1 -ProfileDir "$env:USERPROFILE\ClaudeProfiles\personal"
#>
param(
    [Parameter(Mandatory = $true)]
    [string]$ProfileDir,

    # Optional: give this instance its own Claude Code / Cowork config + memory
    # store by pointing CLAUDE_CONFIG_DIR at a dedicated directory. Useful to
    # keep a personal profile's memory separate from a work one.
    [string]$ConfigDir,

    # Optional: a claude:// link (e.g. the browser's "Open Claude" sign-in link)
    # to hand to this profile. Windows always opens claude:// links in the
    # default profile, so an isolated one only gets them passed like this; if
    # the profile is already running, Chromium forwards the link to that window.
    # Send-ClaudeLink.ps1 wraps this for the clipboard.
    [string]$Url
)

function Show-Error {
    param([string]$Message)
    try {
        Add-Type -AssemblyName PresentationFramework -ErrorAction Stop
        [System.Windows.MessageBox]::Show($Message, 'claude-desktop-clone', 'OK', 'Error') | Out-Null
    } catch {
        Write-Error $Message
    }
}

# Anthropic's MSIX publisher ID (the hash in Claude_<version>_x64__<id>). Pinning
# it means a package from anyone else that merely has "Claude" in its name is
# never launched.
$anthropicPublisherId = 'pzs8sxrjxfjjc'

# 1) Preferred: resolve via the Appx package (robust against version changes).
$exe = $null
try {
    $pkg = Get-AppxPackage -Name '*Claude*' -ErrorAction Stop |
        Where-Object PublisherId -eq $anthropicPublisherId |
        Sort-Object Version -Descending | Select-Object -First 1
    if ($pkg) {
        $candidate = Join-Path $pkg.InstallLocation 'app\Claude.exe'
        if (Test-Path $candidate) { $exe = $candidate }
    }
} catch { }

# 2) Fallback: scan WindowsApps directly (newest version first).
if (-not $exe) {
    $exe = Get-ChildItem "C:\Program Files\WindowsApps\Claude_*__$anthropicPublisherId\app\Claude.exe" -ErrorAction SilentlyContinue |
        Sort-Object FullName -Descending | Select-Object -First 1 -ExpandProperty FullName
}

if (-not $exe -or -not (Test-Path $exe)) {
    Show-Error "Claude Desktop app was not found.`n`nInstall it from the Microsoft Store / claude.ai/download first, then run again."
    exit 1
}

if ($Url -and $Url -notmatch '^claude://[^\s"]+$') {
    Show-Error "Not a claude:// link: only links that start with claude:// can be passed to Claude."
    exit 1
}

# Ensure the isolated data directory exists.
New-Item -ItemType Directory -Force -Path $ProfileDir | Out-Null

# Optionally isolate Claude Code / Cowork config + memory for this instance.
# Start-Process inherits this process's environment, so the launched app (and
# any claude-code it spawns) picks up CLAUDE_CONFIG_DIR.
if ($ConfigDir) {
    New-Item -ItemType Directory -Force -Path $ConfigDir | Out-Null
    $env:CLAUDE_CONFIG_DIR = $ConfigDir
}

# Launch. Different --user-data-dir => separate singleton lock => parallel instance.
# Start-Process doesn't quote arguments, so quote the dir ourselves: unquoted, a
# path with a space (C:\Users\Jane Doe\...) reaches Claude.exe as two arguments.
# A trailing backslash would escape the closing quote, so trim it.
$argList = @("--user-data-dir=`"$($ProfileDir.TrimEnd('\'))`"")
if ($Url) { $argList += "`"$Url`"" }
Start-Process -FilePath $exe -ArgumentList $argList
