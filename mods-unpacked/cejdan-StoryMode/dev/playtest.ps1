# Runs one playtest scenario and exits. Usage (from anywhere, PowerShell):
#   & "<...>\mods-unpacked\cejdan-StoryMode\dev\playtest.ps1" <scenario> [-Timeout 300] [-Headless] [-Res 1280x720] [-Extra "--foo=1"]
# Output lands in ..\playtest_out\<scenario>\ next to the project: screenshots,
# log.json, godot.log. Prints the result and any script errors.
# A scenario that needs longer than 300 s declares `const TIMEOUT := <seconds>`;
# that is used unless -Timeout is given.
param(
    [Parameter(Mandatory = $true)][string]$Scenario,
    [int]$Timeout = 300,
    [switch]$Headless,
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
$argList = @("--path", "`"$project`"", "--windowed", "--resolution", $Res, "--position", "40,40", "--log-file", "`"$log`"")
if ($Headless) { $argList += "--headless" }
$argList += @("--", "--scenario=$Scenario", "`"--out=$out`"")
if ($Extra -ne "") { $argList += $Extra.Split(" ") }
$p = Start-Process -FilePath $engine -ArgumentList $argList -PassThru
if (-not $p.WaitForExit($Timeout * 1000)) {
    Stop-Process -Id $p.Id -Force
    Write-Output "RESULT: TIMEOUT after $Timeout s (killed)"
} else {
    Write-Output "RESULT: exit code $($p.ExitCode)"
}
if (Test-Path $log) {
    $noise = "localization_|unknown win condition|leaked|Can't create shader cache|Condition `"!res.is_valid\(\)`"|translation"
    $errs = Select-String -CaseSensitive -Path $log -Pattern "SCRIPT ERROR|Parse Error|Failed to load script|^ERROR|Invalid call|Invalid access|Nonexistent function|starting Sentry SDK" | Where-Object { $_.Line -notmatch $noise }
    Write-Output "ERRORS: $($errs.Count)"
    $errs | Select-Object -First 25 | ForEach-Object { Write-Output ("  L" + $_.LineNumber + ": " + $_.Line) }
    Select-String -Path $log -Pattern "^\[harness\] (PASS|FAIL)" | ForEach-Object { Write-Output $_.Line }
}
Get-ChildItem $out | Select-Object -ExpandProperty Name | Out-String | Write-Output
