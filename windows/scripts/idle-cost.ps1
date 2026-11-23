# What Notchy costs this machine while nobody is touching it.
#
# Finds coucou.exe and every WebView2 process under it — the island, Settings,
# the clipboard and the pages are each Edge processes of their own, and Task
# Manager files most of them under "Microsoft Edge WebView2", not under Notchy —
# then measures them for a while and prints one line per process and a total.
#
#   powershell -ExecutionPolicy Bypass -File idle-cost.ps1
#   powershell -ExecutionPolicy Bypass -File idle-cost.ps1 -Seconds 120
#
# CPU is a share of the whole machine, as Task Manager shows it: 25 % on a
# four-core PC is one core kept busy. Memory is the private working set, Task
# Manager's "Memory" column. Read-only: it measures and changes nothing.
#
# `-Label` names the run in the summary line, which is a single
# `IDLE label=... processes=... cpu=...% memoryMB=...` line that CI compares
# between builds.

param(
  [int]$Seconds = 60,
  [string]$Name = 'coucou',
  [string]$Label = 'run'
)

$ErrorActionPreference = 'Stop'

function Get-Tree([string]$exe) {
  $all = @(Get-CimInstance Win32_Process)
  $roots = @($all | Where-Object { $_.Name -ieq "$exe.exe" })
  if ($roots.Count -eq 0) { return @() }
  $children = @{}
  foreach ($p in $all) {
    $key = [string]$p.ParentProcessId
    if (-not $children.ContainsKey($key)) { $children[$key] = New-Object System.Collections.ArrayList }
    [void]$children[$key].Add($p)
  }
  $found = New-Object System.Collections.ArrayList
  $queue = New-Object System.Collections.Queue
  foreach ($r in $roots) { $queue.Enqueue($r) }
  $seen = @{}
  while ($queue.Count -gt 0) {
    $p = $queue.Dequeue()
    if ($seen.ContainsKey([string]$p.ProcessId)) { continue }
    $seen[[string]$p.ProcessId] = $true
    [void]$found.Add($p)
    $key = [string]$p.ProcessId
    if ($children.ContainsKey($key)) { foreach ($c in $children[$key]) { $queue.Enqueue($c) } }
  }
  return $found
}

# What a process is, from its command line: the app itself, an Edge browser
# process (one per WebView2 profile folder), or one of its helpers.
function Get-Kind($p) {
  if ($p.Name -ieq "$Name.exe") { return 'app' }
  $cmd = [string]$p.CommandLine
  if ($cmd -match '--type=([a-z-]+)') {
    $kind = $Matches[1]
    if ($kind -eq 'utility' -and $cmd -match '--utility-sub-type=([A-Za-z.]+)') {
      $sub = $Matches[1] -replace '^.*\.', ''
      return "utility:$sub"
    }
    return $kind
  }
  return 'browser'
}

# Which WebView2 profile a browser process runs: the island's own, ChatGPT's or
# WhatsApp's. Its helpers belong to the same one.
function Get-Profile($p, $byId) {
  $cur = $p
  for ($i = 0; $i -lt 4 -and $cur; $i++) {
    $cmd = [string]$cur.CommandLine
    $dir = $null
    if ($cmd -match '--user-data-dir="([^"]+)"') { $dir = $Matches[1] }
    elseif ($cmd -match '--user-data-dir=(\S+)') { $dir = $Matches[1] }
    if ($dir) {
      if ($dir -match 'webchat-webview') { return 'chatgpt' }
      if ($dir -match 'whatsapp-webview') { return 'whatsapp' }
      return 'main'
    }
    $cur = $byId[[string]$cur.ParentProcessId]
  }
  if ($p.Name -ieq "$Name.exe") { return '-' }
  return 'main'
}

function Get-Cpu([int]$id) {
  try { return (Get-Process -Id $id -ErrorAction Stop).TotalProcessorTime.TotalSeconds } catch { return $null }
}

# The private working set of every process, in one query: asking the
# performance classes one process at a time takes seconds each.
function Get-PrivateMap {
  $map = @{}
  try {
    foreach ($row in @(Get-CimInstance Win32_PerfFormattedData_PerfProc_Process -ErrorAction Stop)) {
      $map[[string]$row.IDProcess] = [math]::Round($row.WorkingSetPrivate / 1MB, 1)
    }
  } catch {}
  return $map
}

function Get-PrivateMB([int]$id, $map) {
  if ($map.ContainsKey([string]$id)) { return $map[[string]$id] }
  try { return [math]::Round((Get-Process -Id $id -ErrorAction Stop).PrivateMemorySize64 / 1MB, 1) } catch { return 0 }
}

$tree = @(Get-Tree $Name)
if ($tree.Count -eq 0) {
  Write-Output "$Name.exe is not running."
  exit 1
}

$cores = [Environment]::ProcessorCount
$start = @{}
foreach ($p in $tree) { $start[[string]$p.ProcessId] = Get-Cpu ([int]$p.ProcessId) }
$clock = [Diagnostics.Stopwatch]::StartNew()
Write-Output "Measuring $($tree.Count) processes for $Seconds s on $cores logical cores..."
Start-Sleep -Seconds $Seconds
$elapsed = $clock.Elapsed.TotalSeconds

# Taken again at the end: a process that started meanwhile counts from zero,
# one that ended has nothing left to read and drops out.
$tree = @(Get-Tree $Name)
$byId = @{}
foreach ($p in $tree) { $byId[[string]$p.ProcessId] = $p }
$privMap = Get-PrivateMap

$rows = foreach ($p in $tree) {
  $id = [int]$p.ProcessId
  $now = Get-Cpu $id
  if ($now -eq $null) { continue }
  $was = $start[[string]$id]
  if ($was -eq $null) { $was = 0 }
  [pscustomobject]@{
    Profile = Get-Profile $p $byId
    Kind    = Get-Kind $p
    PID     = $id
    CPU     = [math]::Round(($now - $was) / ($elapsed * $cores) * 100, 2)
    MemMB   = Get-PrivateMB $id $privMap
  }
}

$rows | Sort-Object Profile, Kind | Format-Table -AutoSize | Out-String -Width 200 | Write-Output

$cpu = [math]::Round((($rows | Measure-Object CPU -Sum).Sum), 2)
$mem = [math]::Round((($rows | Measure-Object MemMB -Sum).Sum), 0)
foreach ($group in ($rows | Group-Object Profile | Sort-Object Name)) {
  $gcpu = [math]::Round((($group.Group | Measure-Object CPU -Sum).Sum), 2)
  $gmem = [math]::Round((($group.Group | Measure-Object MemMB -Sum).Sum), 0)
  Write-Output ("  profile {0,-9} {1,3} processes  {2,6} % CPU  {3,6} MB" -f $group.Name, $group.Count, $gcpu, $gmem)
}
Write-Output ""
Write-Output "IDLE label=$Label processes=$(@($rows).Count) cpu=$cpu% memoryMB=$mem seconds=$([math]::Round($elapsed)) cores=$cores"
