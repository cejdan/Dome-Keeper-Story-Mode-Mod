# Keeps playtest windows out of the way of someone using this PC (dot-sourced
# by playtest.ps1 and mp_playtest.ps1). The harness takes its screenshots from
# the game's own viewport, and harness.gd turns off pause-on-focus-loss, so the
# game window can sit off-screen. -Visible on either script puts it back on
# screen.
Add-Type -AssemblyName System.Windows.Forms
if (-not ("PlaytestWin32" -as [type])) {
    Add-Type -Name PlaytestWin32 -Namespace "" -MemberDefinition @"
[DllImport("user32.dll")] public static extern System.IntPtr GetForegroundWindow();
[DllImport("user32.dll")] public static extern bool SetForegroundWindow(System.IntPtr hWnd);
[DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(System.IntPtr hWnd, out uint pid);
"@
}

# A window position (as "x,y" for --position) to the right of every monitor,
# $index windows along.
function Get-OffscreenPosition([int]$index = 0, [int]$width = 1280) {
    $vs = [System.Windows.Forms.SystemInformation]::VirtualScreen
    return ("{0},{1}" -f ($vs.Right + 200 + $index * ($width + 100)), $vs.Top)
}

function Get-ForegroundWindow { return [PlaytestWin32]::GetForegroundWindow() }

# Waits (up to $waitSec) for $proc's window to show, then, if the game took the
# foreground, hands it back to $prev. Returns a short line saying what happened.
function Restore-Foreground([System.IntPtr]$prev, $proc, [int]$waitSec = 15) {
    if ($prev -eq [System.IntPtr]::Zero) { return "focus: no foreground window before launch" }
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    while ($sw.Elapsed.TotalSeconds -lt $waitSec -and -not $proc.HasExited) {
        $proc.Refresh()
        if ($proc.MainWindowHandle -ne [System.IntPtr]::Zero) { break }
        Start-Sleep -Milliseconds 200
    }
    # Godot activates its window a moment after creating it.
    Start-Sleep -Milliseconds 500
    $fg = [PlaytestWin32]::GetForegroundWindow()
    [uint32]$fgPid = 0
    [void][PlaytestWin32]::GetWindowThreadProcessId($fg, [ref]$fgPid)
    if ($fgPid -ne $proc.Id) { return "focus: game did not take the foreground" }
    $ok = [PlaytestWin32]::SetForegroundWindow($prev)
    return $(if ($ok) { "focus: handed back to the previous window" } else { "focus: Windows refused to hand focus back" })
}
