# Adds or removes Coucou's shortcuts: one on the Desktop, one in the Start Menu,
# and optionally one that starts it when you sign in. Everything it touches
# lives in the current user's profile, so it never needs administrator rights.
#
# Driven by "Create shortcuts.cmd" next to it. Coucou has no window and no
# taskbar button, so without a shortcut the only way to launch it a second time
# is to go and find coucou.exe in Explorer.

$ErrorActionPreference = 'Stop'

$here = Split-Path -Parent $MyInvocation.MyCommand.Path

# The portable .zip puts coucou.exe beside this script. A source checkout leaves
# it in windows\target\release, so running this from the repo points the
# shortcuts at the build you just made rather than failing.
$exe = @(
    (Join-Path $here 'coucou.exe'),
    (Join-Path $here '..\target\release\coucou.exe')
) | Where-Object { Test-Path $_ } | Select-Object -First 1

if (-not $exe) {
    Write-Host ''
    Write-Host '  coucou.exe is not next to this script.' -ForegroundColor Red
    Write-Host '  Unzip the whole folder first, then run this from inside it.'
    Write-Host '  (From a source checkout, run `npm run pack` first.)'
    Write-Host ''
    Read-Host '  Press Enter to close'
    exit 1
}
$exe = (Resolve-Path $exe).Path
$fromSource = -not (Test-Path (Join-Path $here 'coucou.exe'))

# GetFolderPath, not "$env:USERPROFILE\Desktop": on a machine where OneDrive has
# taken the Desktop over, the literal path is the wrong folder and the shortcut
# lands somewhere the user never looks. DesktopDirectory is the folder files go
# in; plain Desktop is the shell's virtual one, which is not a place to write.
$desktop   = Join-Path ([Environment]::GetFolderPath('DesktopDirectory')) 'Coucou.lnk'
$startMenu = Join-Path ([Environment]::GetFolderPath('Programs')) 'Coucou.lnk'
$startup   = Join-Path ([Environment]::GetFolderPath('Startup'))  'Coucou.lnk'

function New-Shortcut($path, $target) {
    $dir = Split-Path -Parent $path
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $shell = New-Object -ComObject WScript.Shell
    $lnk = $shell.CreateShortcut($path)
    $lnk.TargetPath       = $target
    $lnk.WorkingDirectory = Split-Path -Parent $target
    $lnk.Description      = 'Mochi at the top of your screen'
    # Explorer would read the icon out of the .exe anyway, but saying so keeps
    # it right when the .exe is replaced in place by a later build.
    $lnk.IconLocation     = "$target,0"
    $lnk.Save()
}

Write-Host ''
Write-Host '  Coucou — shortcuts' -ForegroundColor Cyan
Write-Host "  $exe"
Write-Host ''

if ((Test-Path $desktop) -or (Test-Path $startMenu)) {
    Write-Host '  Coucou already has shortcuts.'
    $answer = Read-Host '  Remove them? (y/N)'
    if ($answer -match '^[yY]') {
        Remove-Item $desktop   -ErrorAction SilentlyContinue
        Remove-Item $startMenu -ErrorAction SilentlyContinue
        Remove-Item $startup   -ErrorAction SilentlyContinue
        Write-Host ''
        Write-Host '  Removed. The folder itself is untouched — delete it to finish.' -ForegroundColor Green
    } else {
        Write-Host '  Left as they are.'
    }
    Write-Host ''
    Read-Host '  Press Enter to close'
    exit 0
}

New-Shortcut $desktop   $exe
New-Shortcut $startMenu $exe
Write-Host '  Added a Coucou icon to your Desktop and your Start Menu.' -ForegroundColor Green

$answer = Read-Host '  Start Coucou when you sign in? (Y/n)'
if ($answer -notmatch '^[nN]') {
    New-Shortcut $startup $exe
    Write-Host '  It will start with Windows.' -ForegroundColor Green
} else {
    Write-Host '  It will not start on its own.'
}

if ($fromSource) {
    Write-Host ''
    Write-Host '  Note: the shortcuts point into target\release, which `cargo clean`' -ForegroundColor Yellow
    Write-Host '  wipes. Run this again after a clean to repoint them.' -ForegroundColor Yellow
}

Write-Host ''
Write-Host '  To open   Double-click the Coucou icon on your Desktop. It has no'
Write-Host '            window and no taskbar button — it opens at the top of the'
Write-Host '            screen. Click it again any time to bring Mochi back down.'
Write-Host '  To close  Right-click the Mochi icon in the notification area, next'
Write-Host '            to the clock, then Quit. Settings... lives there too.'
Write-Host ''
Write-Host '  Hooks: Mochi icon -> Settings... -> Claude Code -> Install hooks...'
Write-Host ''
Read-Host '  Press Enter to close'
