# Runs an online multiplayer playtest on this machine (#223): a host instance
# and a client instance over ENet on 127.0.0.1, each driven by its own scenario.
# Usage (PowerShell):
#   & "<...>\mods-unpacked\flantor-StoryMode\dev\mp_playtest.ps1" <host scenario> <client scenario> [-Timeout 420] [-Res 960x540]
#       [-ClientDelay 6] [-Client2 <scenario>] [-Rejoin <scenario>] [-RejoinDelay 0] [-Visible]
# The windows open off-screen and focus goes back to the window that had it
# (window_place.ps1); -Visible tiles them on screen as before.
# -ClientDelay: seconds between starting the host and the client(s) (a host that
#   loads a save needs longer before it listens).
# -Client2: a second client (a third instance), started with the first (#246).
# -Rejoin: a client started once the last client listed (-Client2 if given, else
#   the client) has exited, after -RejoinDelay seconds: a player who left joins
#   the run under way again, in a new process (#232).
# Output: ..\playtest_out\<scenario>\ for each, as playtest.ps1, and the same
# error scan (log_scan.ps1) and VERDICT line over every instance.
param(
    [Parameter(Mandatory = $true)][string]$HostScenario,
    [Parameter(Mandatory = $true)][string]$ClientScenario,
    [int]$Timeout = 420,
    [string]$Res = "960x540",
    [string]$Extra = "",
    [int]$ClientDelay = 6,
    [string]$Client2 = "",
    [string]$Rejoin = "",
    [int]$RejoinDelay = 0,
    [switch]$Visible
)
$project = (Resolve-Path (Join-Path $PSScriptRoot "..\..\..")).Path
$root = Split-Path $project -Parent
$engine = Join-Path $root "custom_godot_for_windows\godot.windows.editor.x86_64.exe"
if (-not (Test-Path (Join-Path $project "override.cfg"))) { Write-Error "override.cfg missing: refusing to launch"; exit 3 }
$w = [int]($Res.Split("x")[0])
$hgt = [int]($Res.Split("x")[1])
. (Join-Path $PSScriptRoot "window_place.ps1")
# The machine-wide playtest lock (playtest_out/run_locked.ps1 takes the same
# one): only one playtest at a time, and the ENet port is shared.
$lock = New-Object System.Threading.Mutex($false, "Global\StoryModePlaytest")
$waited = [System.Diagnostics.Stopwatch]::StartNew()
try { [void]$lock.WaitOne() } catch [System.Threading.AbandonedMutexException] { }
if ($waited.Elapsed.TotalSeconds -gt 2) { Write-Output ("(waited {0:N0} s for another playtest to finish)" -f $waited.Elapsed.TotalSeconds) }
try {
function Start-Instance($scenario, $pos, [int]$slot) {
    if (-not $Visible) { $pos = Get-OffscreenPosition $slot $w }
    $out = Join-Path $root "playtest_out\$scenario"
    if (Test-Path $out) { Remove-Item -Recurse -Force $out }
    New-Item -ItemType Directory -Force $out | Out-Null
    $log = Join-Path $out "godot.log"
    $argList = @("--path", "`"$project`"", "--windowed", "--resolution", $Res, "--position", $pos, "--log-file", "`"$log`"", "--", "--scenario=$scenario", "`"--out=$out`"")
    if (-not $Visible) { $argList += "--offscreen=$pos" }
    if ($Extra -ne "") { $argList += $Extra.Split(" ") }
    $prevFg = Get-ForegroundWindow
    $proc = Start-Process -FilePath $engine -ArgumentList $argList -PassThru
    if (-not $Visible) { Write-Host (Restore-Foreground $prevFg $proc) }
    $null = $proc.Handle   # keeps the exit code readable after HasExited
    return $proc
}
$hostProc = Start-Instance $HostScenario "20,40" 0
Start-Sleep -Seconds $ClientDelay
$clientProc = Start-Instance $ClientScenario ("{0},40" -f (40 + $w)) 1
$runs = @(@($HostScenario, $hostProc), @($ClientScenario, $clientProc))
$lastClient = $clientProc
$lastPos = ("{0},40" -f (40 + $w))
if ($Client2 -ne "") {
    Start-Sleep -Seconds 3
    $lastPos = ("20,{0}" -f (80 + $hgt))
    $client2Proc = Start-Instance $Client2 $lastPos 2
    $runs += ,@($Client2, $client2Proc)
    $lastClient = $client2Proc
}
$deadline = (Get-Date).AddSeconds($Timeout)
$rejoinProc = $null
$rejoinAt = $null
while ((Get-Date) -lt $deadline) {
    if ($Rejoin -ne "" -and $rejoinProc -eq $null) {
        if ($lastClient.HasExited -and $rejoinAt -eq $null) { $rejoinAt = (Get-Date).AddSeconds($RejoinDelay) }
        if ($rejoinAt -ne $null -and (Get-Date) -ge $rejoinAt) {
            $rejoinProc = Start-Instance $Rejoin $lastPos 3
            $runs += ,@($Rejoin, $rejoinProc)
        }
    }
    $alive = @($runs | Where-Object { -not $_[1].HasExited })
    if ($alive.Count -eq 0 -and ($Rejoin -eq "" -or $rejoinProc -ne $null)) { break }
    if ($hostProc.HasExited -and $rejoinProc -eq $null -and $Rejoin -ne "" -and $rejoinAt -eq $null) { break }
    Start-Sleep -Milliseconds 500
}
foreach ($r in $runs) {
    $p = $r[1]
    if (-not $p.HasExited) { Stop-Process -Id $p.Id -Force; $p | Add-Member -NotePropertyName Killed -NotePropertyValue $true }
}
$ok = $true
if ($Rejoin -ne "" -and $rejoinProc -eq $null) { Write-Output "=== $Rejoin"; Write-Output "RESULT: NOT STARTED (the client before it never exited)"; $ok = $false }
# Error lines on every instance, with USER ERRORs inside each one's scenario,
# minus the allowlist (#249).
. (Join-Path $PSScriptRoot "log_scan.ps1")
foreach ($pair in $runs) {
    $sc = $pair[0]; $p = $pair[1]
    Write-Output "=== $sc"
    if ($p.Killed) { Write-Output "RESULT: TIMEOUT (killed)"; $ok = $false } else {
        Write-Output "RESULT: exit code $($p.ExitCode)"
        if ($p.ExitCode -ne 0) { $ok = $false }
    }
    $log = Join-Path $root "playtest_out\$sc\godot.log"
    if (Test-Path $log) {
        $scan = Invoke-LogScan $log
        $scan.Text | ForEach-Object { Write-Output $_ }
        if ($scan.Count -gt 0) { $ok = $false }
        Select-String -Path $log -Pattern "^\[harness\] (PASS|FAIL)" | ForEach-Object { Write-Output $_.Line }
    } else { $ok = $false }
}
# PASS needs every instance to exit 0 with no unexpected error lines.
Write-Output ("VERDICT: " + $(if ($ok) { "PASS" } else { "FAIL" }) + " " + (($runs | ForEach-Object { $_[0] }) -join " + "))
} finally {
    $lock.ReleaseMutex()
    $lock.Dispose()
}
exit $(if ($ok) { 0 } else { 1 })
