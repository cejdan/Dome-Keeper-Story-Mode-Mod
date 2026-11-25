# Starts a dev run for hand playtesting (#292). Usage (PowerShell, or double-click play_dev.bat):
#   & "<...>\mods-unpacked\flantor-StoryMode\dev\play_dev.ps1" [-Story] [-Money 100000] [-Gear] [-NoUnlock] [-Extra "--seed=12345"]
# By default it opens the loadout with every dome, keeper, mode and gadget
# unlocked (--unlockall) and gives each Story Mode run $100,000 to start.
#   -Story     skip the loadout: straight into a Story Mode run
#   -Money N   starting money for each Story Mode run (0 for none)
#   -Gear      each Story Mode run starts with the boss gear (max drill and
#              jetpack, the dome's top weapon, Heat Shielding IV, Suit Blaster)
#   -NoUnlock  leave the unlocks as the dev profile has them
#   -Extra     more dev switches, e.g. "--gas" (F10) or "--lava" (F9)
#              or "--tentacles --keeper=keeper3" (the tentacle test room, #359)
# In the run, F1 opens the cheat panel; its first column is Story Mode's.
# Runs use the dev profile (%APPDATA%\StoryModeDev, from override.cfg), never
# the real saves.
param(
    [switch]$Story,
    [int]$Money = 100000,
    [switch]$Gear,
    [switch]$NoUnlock,
    [string]$Extra = ""
)
$project = (Resolve-Path (Join-Path $PSScriptRoot "..\..\..")).Path
$root = Split-Path $project -Parent
$engine = Join-Path $root "custom_godot_for_windows\godot.windows.editor.x86_64.exe"
if (-not (Test-Path (Join-Path $project "override.cfg"))) { Write-Error "override.cfg missing: refusing to launch (it keeps dev runs out of the real saves)"; exit 3 }
if (-not (Test-Path $engine)) { Write-Error "Engine not found: $engine"; exit 3 }
$argList = @("--path", "`"$project`"", "--")
$argList += $(if ($Story) { "--story" } else { "--loadout" })
if (-not $NoUnlock) { $argList += "--unlockall" }
if ($Money -gt 0) { $argList += "--money=$Money" }
if ($Gear) { $argList += "--gear" }
if ($Extra -ne "") { $argList += $Extra.Split(" ") }
Write-Output ("Launching: " + ($argList -join " "))
Start-Process -FilePath $engine -ArgumentList $argList
