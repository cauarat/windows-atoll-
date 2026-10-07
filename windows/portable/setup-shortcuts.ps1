# Adds or removes Coucou's Start Menu shortcut, and optionally starts it at
# sign-in. Everything it touches lives in the current user's profile, so it
# never needs administrator rights.
#
# Driven by "Add to Start Menu.cmd" next to it. The portable build has no
# installer, and an app with no taskbar entry and no window is hard to launch
# a second time without this.

$ErrorActionPreference = 'Stop'

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$exe  = Join-Path $here 'coucou.exe'

if (-not (Test-Path $exe)) {
    Write-Host ''
    Write-Host '  coucou.exe is not next to this script.' -ForegroundColor Red
    Write-Host '  Unzip the whole folder first, then run this from inside it.'
    Write-Host ''
    Read-Host '  Press Enter to close'
    exit 1
}

$startMenu = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Coucou.lnk'
$startup   = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Startup\Coucou.lnk'

function New-Shortcut($path, $target) {
    $dir = Split-Path -Parent $path
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $shell = New-Object -ComObject WScript.Shell
    $lnk = $shell.CreateShortcut($path)
    $lnk.TargetPath       = $target
    $lnk.WorkingDirectory = Split-Path -Parent $target
    $lnk.Description      = 'Mochi at the top of your screen'
    $lnk.Save()
}

Write-Host ''
Write-Host '  Coucou — portable setup' -ForegroundColor Cyan
Write-Host "  $exe"
Write-Host ''

$installed = Test-Path $startMenu
if ($installed) {
    Write-Host '  Coucou is already in your Start Menu.'
    $answer = Read-Host '  Remove it? (y/N)'
    if ($answer -match '^[yY]') {
        Remove-Item $startMenu -ErrorAction SilentlyContinue
        Remove-Item $startup   -ErrorAction SilentlyContinue
        Write-Host ''
        Write-Host '  Removed. The folder itself is untouched — delete it to finish.' -ForegroundColor Green
    } else {
        Write-Host '  Left as it is.'
    }
    Write-Host ''
    Read-Host '  Press Enter to close'
    exit 0
}

New-Shortcut $startMenu $exe
Write-Host '  Added to the Start Menu.' -ForegroundColor Green

$answer = Read-Host '  Start Coucou when you sign in? (Y/n)'
if ($answer -notmatch '^[nN]') {
    New-Shortcut $startup $exe
    Write-Host '  It will start with Windows.' -ForegroundColor Green
} else {
    Write-Host '  It will not start on its own.'
}

Write-Host ''
Write-Host '  Press the Windows key and type "Coucou" to launch it.'
Write-Host '  Then open Settings... -> Claude Code -> Install hooks... from the'
Write-Host '  Mochi icon in the notification area, next to the clock.'
Write-Host ''
Read-Host '  Press Enter to close'
