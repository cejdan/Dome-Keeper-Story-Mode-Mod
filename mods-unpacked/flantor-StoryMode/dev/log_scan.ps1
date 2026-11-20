# Error scan for one instance's godot.log (#249), dot-sourced by playtest.ps1
# and mp_playtest.ps1.
#
# Counted anywhere in the log (as before #249): SCRIPT ERROR (and USER SCRIPT
# ERROR), Parse Error, Failed to load script, lines starting ERROR, Invalid
# call / access, Nonexistent function, a Sentry start, and since #252 the
# compiler's "unresolved assign" (a script compiled after an extension took
# its class_name; extensions/installer.gd).
# Counted between "[harness] scenario begin" and "[harness] scenario end" (to the
# end of the log if the run never got there; the whole log if it never began):
# USER ERROR lines too. That is where push_error and engine errors from mod
# code show up (a lambda-capture error in boss/sfx.gd stayed silent this way).
#
# Every error line is matched together with the line after it (its "at:" line,
# which names the script or engine function), against the allowlist below. A
# line no entry matches fails the run. Keep the list short; each entry says
# where its lines come from and why they are not ours to fix.

$script:LogScanAllow = @(
    # Vanilla project.godot lists translations the shipped game does not have
    # (localization_bg_BG ... localization_eu_ES): two lines each at boot.
    @{ Name = "localization"; Pattern = 'localization_[a-zA-Z_]+\.[a-zA-Z_]+\.translation' },
    # Engine reports at exit, after the scenario ends: RIDs, textures, ObjectDB
    # and resources still alive when the SceneTree quits from a script.
    @{ Name = "exit leaks"; Pattern = 'leaked|resources still in use at exit|Parameter "RenderingServer::get_singleton\(\)" is null' },
    # Online clients: vanilla Synchronizer.gd's _remote_set_initial_data takes
    # (tick, buffer); DataSynchronizer.gd sends it through the chunker with three
    # (tick, size, compressed buffer), so every client logs the call failing.
    # Harmless: Client.full_data_sync delivers the same full sync. Reported on
    # #249; not in any godot.log of the 2026-11-17 suite run, kept for when it is.
    @{ Name = "datasync args"; Pattern = '_remote_set_initial_data' },
    # Loading a save: vanilla Map.deserialize calls init(true) on a map already
    # initialised, and CentralMarker.init connects keeper_registered again.
    @{ Name = "save load (CentralMarker)"; Pattern = "keeper_registered' is already connected to given callable 'Line2D\(CentralMarker\.gd\)" },
    # Online host, a player leaving while a teleporter sits in its station:
    # vanilla TeleporterStation.on_keeper_removed reads the unset teleporter.
    @{ Name = "teleporter station"; Pattern = "'teleporting' on a base object of type 'Nil'.*TeleporterStation\.on_keeper_removed" },
    # Vanilla's supplement choice (a power core delivered) builds the icon path
    # from the player-scoped upgrade id; Data.loadIconOrFallback logs the miss
    # and falls back to the default icon.
    @{ Name = "supplement icon"; Pattern = 'No loader found for resource: res://content/icons/player[0-9]+\.' },
    # Vanilla RemoteControlStation.gd's reveal tick makes a tween each second
    # and adds a callback per hidden tile nearby; with none hidden it is empty.
    @{ Name = "remote control reveal"; Pattern = 'RemoteControlStation\): started with no Tweeners' },
    # Vanilla furnace: FurnaceStation has no state_changed signal for its
    # GadgetSynchronizer (online), and FurnaceStation.gd reads
    # get_meta("tween", null), which logs when the meta is missing.
    # Vanilla DomeArmor.gd listens to domearmor.pulsedamagethreshold with an
    # immediate call; at 0 its propertyChanged unlistens dome.health, which it
    # never listened to (any run that installs the Dome Armor, #234).
    @{ Name = "vanilla dome armor"; Pattern = 'removing listener who is not listening Data: \{"listener":"DomeArmor:' },
    @{ Name = "vanilla furnace"; Pattern ="FurnaceStation/GadgetSynchronizer is parented to a gadget without a state_changed|does not have any 'meta' values with the key 'tween'" },
    # Vanilla Relic Hunt's final act with the harness's waves forced
    # (t54_vanilla): Wave.gd reads monsters.timingmod before Monsters.gd has
    # set it, and GameWorld re-adds the between_waves limit.
    @{ Name = "vanilla forced waves"; Pattern = 'unknown data team[0-9]+\.monsters\.timingmod|tech limit that.s already available Data: "team[0-9]+\.between_waves"' },
    # Online host, as it leaves the loadout for the run: the client's loadout
    # keeper still sends KeeperSynchronizer packets for a node the host has
    # just freed. Vanilla: a relichunt pair logs the same (#249).
    @{ Name = "loadout teardown"; Pattern = 'MultiplayerLoadoutStage/.*/player[0-9]+/KeeperSynchronizer' },
    # Online host, as a client quits: for a few frames the ENet peer is
    # disconnecting (its channels gone) but not yet removed, and whatever sends
    # to it then (vanilla's syncs as much as ours) is dropped by the engine.
    @{ Name = "client leaving"; Pattern = 'Unable to send packet on channel 0, max channels: 0' },
    # Vanilla's keeper choice (DeviceSelection stage; loading an online save,
    # #232/#251): a player takes a keeper, vanilla's spawner frees the dummy
    # it walked in as, and a KeeperSynchronizer packet the other instance sent
    # for the dummy before it heard lands for a node that is gone (one or two
    # lines, like "loadout teardown"). The race that left a client without
    # its keeper and logged this every frame (and Keeper.updatePlayerName's
    # 'platform_id' on Nil) is avoided in Story Mode since #251.
    @{ Name = "keeper choice: freed dummy"; Pattern = 'DeviceSelectionStage/DeviceSelectionStage/player1[0-9][0-9]/KeeperSynchronizer' },
    # Vanilla Dome.unlisten (content/dome/Dome.gd:118-120) drops inventory
    # iron/water/sand listeners that only some domes added; a dome swapped out
    # in the loadout logs three lines. Relic Hunt does the same (t28_loadout's
    # swap there, #269); Story Mode offers every dome since #269.
    # Swapping back to a dome picked before in the same loadout re-adds its
    # limit (GameWorld.setUpgradeLimitAvailable; Relic Hunt in t28_loadout).
    @{ Name = "vanilla dome swap"; Pattern = 'removing listener who is not listening Data: \{"listener":"team[0-9]+Dome:<Node2D#[0-9]+>","property":"team[0-9]+\.inventory\.(iron|water|sand)"\}|tech limit that.s already available Data: "team[0-9]+\.dome[0-9]"' },
    # Engine audio driver (drivers\wasapi\audio_driver_wasapi.cpp): the
    # machine's audio device hiccups mid-run (seen once in t269_dome2, #269).
    @{ Name = "engine audio (WASAPI)"; Pattern = 'WASAPI: GetBufferSize error' }
)

# The engine logs these right after one of the lines above, about the same
# packet: allowed only straight after an allowed line.
$script:LogScanFollowers = 'Parameter "node" is null\.|Failed to get path from RPC|Invalid packet received\. Requested node was not found|Failed to get cached node from peer'

# Returns { Count = unexpected error lines; Text = lines to print }.
function Invoke-LogScan([string]$log) {
    $lines = @(Get-Content -LiteralPath $log -Encoding UTF8)
    $begin = -1; $end = $lines.Count - 1
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($begin -lt 0 -and $lines[$i].StartsWith("[harness] scenario begin")) { $begin = $i }
        elseif ($begin -ge 0 -and $lines[$i].StartsWith("[harness] scenario end")) { $end = $i; break }
    }
    $anywhere = 'SCRIPT ERROR|Parse Error|Failed to load script|^ERROR|Invalid call|Invalid access|Nonexistent function|starting Sentry SDK|Compiler bug'
    $bad = @()
    $allowed = [ordered]@{}
    $prevAllowed = -10
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $l = $lines[$i]
        $inWindow = ($begin -lt 0) -or ($i -ge $begin -and $i -le $end)
        $hit = ($l -cmatch $anywhere) -or ($inWindow -and $l.StartsWith("USER ERROR"))
        if (-not $hit) { continue }
        $next = if ($i + 1 -lt $lines.Count) { $lines[$i + 1].Trim() } else { "" }
        $both = "$l || $next"
        $name = $null
        foreach ($a in $script:LogScanAllow) { if ($both -match $a.Pattern) { $name = $a.Name; break } }
        if ($name -eq $null -and ($i - $prevAllowed) -le 3 -and $l -match $script:LogScanFollowers) { $name = "(same packet)" }
        if ($name -ne $null) {
            $allowed[$name] = 1 + $(if ($allowed.Contains($name)) { $allowed[$name] } else { 0 })
            $prevAllowed = $i
        } else {
            $bad += ,@(($i + 1), ($l + $(if ($next.StartsWith("at:")) { "   [" + $next + "]" } else { "" })))
        }
    }
    $window = if ($begin -lt 0) { "no scenario begin: whole log" } else { "scenario L$($begin + 1)-L$($end + 1)" }
    $allowText = ($allowed.Keys | ForEach-Object { "$_ x$($allowed[$_])" }) -join ", "
    $text = @("ERRORS: {0}  ({1}; allowed: {2})" -f $bad.Count, $window, $(if ($allowText) { $allowText } else { "none" }))
    # One row per distinct line: where it first shows and how often.
    $seen = [ordered]@{}
    foreach ($b in $bad) {
        if ($seen.Contains($b[1])) { $seen[$b[1]][1] += 1 } else { $seen[$b[1]] = @($b[0], 1) }
    }
    $text += @($seen.Keys | Select-Object -First 25 | ForEach-Object { "  L{0}{1}: {2}" -f $seen[$_][0], $(if ($seen[$_][1] -gt 1) { " (x" + $seen[$_][1] + ")" } else { "" }), $_ })
    return [pscustomobject]@{ Count = $bad.Count; Text = $text }
}
