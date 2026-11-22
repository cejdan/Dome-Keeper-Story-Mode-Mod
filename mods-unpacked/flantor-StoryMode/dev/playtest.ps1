# Runs one playtest scenario and exits. Usage (from anywhere, PowerShell):
#   & "<...>\mods-unpacked\flantor-StoryMode\dev\playtest.ps1" <scenario> [-Timeout 300] [-Headless] [-Visible] [-Res 1280x720] [-Extra "--foo=1"]
# Output lands in ..\playtest_out\<scenario>\ next to the project: screenshots,
# log.json, godot.log. Prints the result, the error lines log_scan.ps1 finds
# (#249) and a VERDICT line; exits 0 when the run passed and the log is clean.
# A scenario that needs longer than 300 s declares `const TIMEOUT := <seconds>`;
# that is used unless -Timeout is given.
# The window opens off-screen and focus goes back to the window that had it
# (window_place.ps1); -Visible opens it on screen at 40,40 as before.
param(
    [Parameter(Mandatory = $true)][string]$Scenario,
    [int]$Timeout = 300,
    [switch]$Headless,
    [switch]$Visible,
    [string]$Res = "1280x720",
    [string]$Extra = ""
)
$project = (Resolve-Path (Join-Path $PSScriptRoot "..\..\..")).Path
$root = Split-Path $project -Parent
$engine = Join-Path $root "custom_godot_for_windows\godot.windows.editor.x86_64.exe"
$out = Join-Path $root "playtest_out\$Scenario"
if (-not (Test-Path (Join-Path $project "override.cfg"))) { Write-Error "override.cfg missing: refusing to launch"; exit 3 }
if (-not $PSBoundParameters.ContainsKey("Timeout")) {
    $src = Join-Path $PSScriptRoot "scenarios\$Scenario.gd"
    $decl = if (Test-Path $src) { Select-String -Path $src -Pattern "^const TIMEOUT\s*:?=\s*(\d+)" | Select-Object -First 1 } else { $null }
    if ($decl) { $Timeout = [int]$decl.Matches[0].Groups[1].Value }
}
if (Test-Path $out) { Remove-Item -Recurse -Force $out }
New-Item -ItemType Directory -Force $out | Out-Null
$log = Join-Path $out "godot.log"
. (Join-Path $PSScriptRoot "window_place.ps1")
$pos = if ($Visible) { "40,40" } else { Get-OffscreenPosition 0 ([int]($Res.Split("x")[0])) }
$argList = @("--path", "`"$project`"", "--windowed", "--resolution", $Res, "--position", $pos, "--log-file", "`"$log`"")
if ($Headless) { $argList += "--headless" }
$argList += @("--", "--scenario=$Scenario", "`"--out=$out`"")
if (-not $Visible) { $argList += "--offscreen=$pos" }
if ($Extra -ne "") { $argList += $Extra.Split(" ") }
$prevFg = Get-ForegroundWindow
$p = Start-Process -FilePath $engine -ArgumentList $argList -PassThru
if (-not $Visible) { Write-Output (Restore-Foreground $prevFg $p) }
$ok = $true
if (-not $p.WaitForExit($Timeout * 1000)) {
    Stop-Process -Id $p.Id -Force
    Write-Output "RESULT: TIMEOUT after $Timeout s (killed)"
    $ok = $false
} else {
    Write-Output "RESULT: exit code $($p.ExitCode)"
    if ($p.ExitCode -ne 0) { $ok = $false }
}
if (Test-Path $log) {
    # Error lines, with USER ERRORs inside the scenario, minus the allowlist (#249).
    . (Join-Path $PSScriptRoot "log_scan.ps1")
    $scan = Invoke-LogScan $log
    $scan.Text | ForEach-Object { Write-Output $_ }
    if ($scan.Count -gt 0) { $ok = $false }
    Select-String -Path $log -Pattern "^\[harness\] (PASS|FAIL)" | ForEach-Object { Write-Output $_.Line }
} else { $ok = $false }
Get-ChildItem $out | Select-Object -ExpandProperty Name | Out-String | Write-Output
# PASS needs exit code 0 and no unexpected error lines; the script's own exit
# code says the same (0 / 1).
Write-Output ("VERDICT: " + $(if ($ok) { "PASS" } else { "FAIL" }) + " $Scenario")
exit $(if ($ok) { 0 } else { 1 })
