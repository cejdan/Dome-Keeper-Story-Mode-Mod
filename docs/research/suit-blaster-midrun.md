# Granting the Suit Blaster mid-run

Research for [#18](https://github.com/cejdan/Dome-Keeper-Story-Mode-Mod/issues/18), feeding [#19](https://github.com/cejdan/Dome-Keeper-Story-Mode-Mod/issues/19) (how it is sold), [#22](https://github.com/cejdan/Dome-Keeper-Story-Mode-Mod/issues/22) (shop task) and [#20](https://github.com/cejdan/Dome-Keeper-Story-Mode-Mod/issues/20) (metal gate tile).

All sources are the decompiled game in this folder (Godot 4.3, ModLoader 7.0.1). Line numbers are from that source as of 2026-11-10.

## Short answer

The ticket's premise is off. The Suit Blaster is not a loadout pick. In vanilla it is a mid-run gadget: you dig up a gadget chest, carry it to the dome, and choose it from the offer popup. Granting it mid-run is a path the game already uses, and it is one call:

```gdscript
GameWorld.serverAddUpgrade("player1.suitblaster", "team1")
```

That call equips the blaster on the keeper, adds its HUD, queues its tutorial, makes its upgrade tree show in the tech tree, and survives save/load. Nothing has to be patched for it to work. The work is in how the shop sells it (a shop entry needs a mod-defined proxy upgrade, see below) and in keeping vanilla gadget chests from giving it away or filling its slot.

## How gadgets reach the keeper

### Loadout "primary gadget" is a dome gadget, not the Suit Blaster

`LevelStage.gd:223-239` applies the loadout at level start:

- `loadoutDome.primaryGadgetId` goes through `GameWorld.addUpgrade(pgid, teamId)`. These are the dome gadgets (`repellent`, `shield`, `orchard`, `droneyard`; see `GameWorld.prepareUnlockables`, `GameWorld.gd:813-835`).
- `loadoutDome.additionalGadgets` are the Guild/Assignment extra gadgets (`AdditionalGadgetPopup.gd`, `Loadout.gd:133-136`). Keepersuit gadgets get a player prefix there: `GameWorld.addUpgrade(keeper.playerId + "." + gadgetId, teamId)`.

`prepareGameMode` (`GameWorld.gd:340-341`) is a hook for mods: every node in group `gamemodes-prepare` gets `prepareGameMode(modeId, levelStartData)` before the level is built. It runs too early to add a keeper gadget (no keeper exists yet), but it is the right place for Story Mode to set gadget-chest rules (below).

`GameWorld.unlockElement` (`GameWorld.gd:773`) only affects meta-progression (what the loadout screen offers, what appears in chests via `unlocks.is_unlocked`). `addUpgrade` never checks it, so a direct grant works even on a fresh profile like the dev user folder.

### The vanilla mid-run path

1. A gadget drop delivered to the dome calls `Level.stage.queueChoice(CONST.GADGET, teamId, playerId)` (the same call the cheat menu uses, `Cheats.gd:472-474`).
2. `LevelStage.generateOffers` (`LevelStage.gd:709`) builds offers with `GameWorld.generateGadgets` (`GameWorld.gd:1427`). For keepersuit gadgets, `modifyUpgradeDataForGadgetPopup` calls `Data.asKeeperGadget`, so the offered id is `player1.suitblaster`.
3. On pick, `LevelStage.addGadgetUpgrade` (`LevelStage.gd:801-815`) validates and calls `GameWorld.serverAddUpgrade(id, teamId)`.

The cheat menu's gadget list does the same thing directly (`Cheats.gd:344-356`): for keepersuit gadgets it calls `GameWorld.serverAddUpgrade(keeper.playerId + "." + text, keeper.teamId)`. Relic Hunt's "kept gadget" does it with `addUpgrade("player1." + gadgetId, teamId)` from the mode script (`Relichunt.gd:27-38`).

### What `addUpgrade("player1.suitblaster", "team1")` does

From `GameWorld.addUpgrade` (`GameWorld.gd:1090-1288`):

- The `id.count(".") > 0` branch sets `perPlayer = "player1"` and copies `Data.upgrades["suitblaster"]` (gadgets are also stored in `Data.upgrades`, `Data.gd:513-516`).
- `Data.asKeeperGadget` (`Data.gd:897`) rewrites `takeslots: [keepersuit]` to `player1.keepersuit` and `addslots` to `player1.suitblastersupplement`. `Data.makeInstancedUpgrade(..., "team1")` (`Data.gd:879`) prefixes the property keys, giving `team1.suitblaster.radius`, `team1.suitblaster.maxcharge`, and so on. `SuitBlaster.gd` reads these through `teamId`.
- The id goes into `boughtUpgrades`, the slot is taken, and the property changes are applied (server only).
- Scene `keepersuit`: `trackAdditionalGadget` records it in `addedGadgetIds`, then `Keepers.getKeeper("player1").addAddition(instance)` (`Keeper.gd:436`) parents `SuitBlaster.tscn` to the keeper and sets its team and player ids.
- Scene `hud`: `Level.addHudElement(scene, "player1")` adds `SuitBlasterHud` to that player's HUD at runtime.
- `updateAvailableUpgrades("team1")` runs at the end, which brings in the upgrade tree (next section).

`serverAddUpgrade` (`GameWorld.gd:988`) wraps this with the `upgradeAdded` signal, a data sync tick and the client RPC. Use it rather than bare `addUpgrade` during a run.

## The keepersuit slot

Each keeper adds one `keepersuit` slot and one `keepersupplement` slot (`upgrades.yaml`: `keeper1` at line 527, and likewise for keepers 2-4). Four gadgets compete for the keepersuit slot:

| Gadget | `takeslots` | upgrades.yaml |
|---|---|---|
| `probe` | `[cellar, keepersuit]` | 2838 |
| `prospectionmeter` | `[keepersuit]` | 3064 |
| `suitblaster` | `[keepersuit]` | 3114 |
| `resourcepacker` | `[keepersuit]` | 3603 |

So one keeper carries only one of them at a time. `keeperonewayteleporter` has a `keepersuit` scene, but it is a supplement that takes `keepersupplement`, so it does not compete. The keeper-specific items (`keeper1powerdrill` and the others) are supplements too.

`addUpgrade` does not check slots (only `isUpgradeAddable` and the offer generators do), so a forced grant on a keeper that already holds, say, a Probe would add the Suit Blaster anyway with the slot already gone. Probably harmless in play, but the state is not one vanilla expects. Story Mode should make sure the slot is free (next section) and check `GameWorld.areUpgradeSlotsAvailable` before granting.

## Does the HUD, tutorial or tree assume a loadout pick?

No. All three are built for the mid-run chest path.

- **HUD:** added on grant by `Level.addHudElement`. `SuitBlasterHud.gd` only listens to `player1.suitblaster.charge` and `team1.suitblaster.maxcharge`.
- **Tutorial:** `SuitBlaster._ready` calls `Level.addTutorial(self, "suitblaster", playerId)` (`Level.gd:36`). That adds the tutorial to the player's `TutorialManager` if it hasn't timed out. `SuitBlasterTutorial` fires once the keeper is below y=100 and confirms on the first blast. Tutorial progress is global (`GameWorld.tutorialStages`, persisted), so it shows once per profile, not once per run. The text (`localization.csv:2034-2036`) is generic.
- **Charge:** `_ready` starts the charge at 1.0, so the first blast is ready at once. Recharge runs at `chargespeed / getTimeBetweenWaves` and stops while `GameWorld.softPaused(teamId)` is true.
- **Input:** `SuitBlaster.tscn` is in group `special1`. `KeeperInputProcessor.gd:214-219` looks the group up on each `keeper_gadget1` press, so a blaster added mid-run works right away. It only fires outside the dome.
- **Upgrade tree in the shop:** yes, it appears. `Data.parseUpgradesYaml` flags tier-1 children of a keepersuit gadget as `followskeepergadget` (`Data.gd:570-571`). `Data.asKeeperGadgetUpgrade` (`Data.gd:957`) then sets their predecessor to `player1.suitblaster` when `updateAvailableUpgrades` instances them. `TechTree.calculateTracks` (`TechTree.gd:39`) makes a track for each bought tier-0 entry, so `player1.suitblaster` becomes a track with `suitblasterMaxCharge`, `suitblasterSpeed1` and their children. Their costs are vanilla `iron=`/`water=` until #12's repricing covers them.
  - One UI catch: `TechTreePopup` builds its tree in `_ready` (`TechTreePopup.gd:16`). `TechTree.onUpgradeAdded` only refreshes tracks that already exist (`TechTree.gd:221-258`). If the blaster is bought from inside the open tech tree, its new track shows after the popup is closed and reopened. Fixing that means rebuilding the tree on that purchase, which a small script extension or a manual `calculateTracks`/rebuild could do.
- **Save/load:** `player1.suitblaster` sits in `BoughtUpgrades` and `addedGadgetIds`, and is replayed like any chest gadget. `LevelKeeperSpawner.gd:37-53` re-adds keepersuit scenes to a respawned keeper from `addedGadgetIds`.

## Selling it from the shop

The tech tree can't list an unbought gadget. Tracks start only from tier-0 entries that are already bought (`TechTree.gd:52-55`). `GameWorld.buyUpgrade` and `requestUpgrade` (`GameWorld.gd:954`, `1009`) only buy ids already in `GameWorld.upgrades`, and an unbought gadget isn't there. So `suitblaster` can't be given a price and shown as-is.

**Recommended: a proxy shop upgrade plus a signal listener. No vanilla patch is needed.**

1. In the mod's upgrade data (whatever mechanism #12 lands for a mod `upgrades.yaml`), define a Story Mode root and a purchasable entry:
   ```yaml
   storymode:
     type: gamemode
   storySuitblaster:
     cost: money=<price from #19>
     predecessors: [storymode]
   ```
   `GameWorld.levelInitialized` (`GameWorld.gd:497-505`) adds the mode's own gamemode upgrade automatically whenever some upgrade lists the mode id as a predecessor. That's how `prestige` gets its tree. `team1.storymode` becomes a bought tier-0 root, and its track shows `storySuitblaster` as a buyable tier-1 panel. The id must equal Story Mode's `modeId`. Gamemode entries are skipped by gadget offers, which filter `type == "gadget"`.
2. In `mod_main.gd`, connect `GameWorld.upgradeBought(id, teamId, playerId)`. It fires on the server after the cost is paid (`GameWorld.gd:965-969`). When `id == teamId + ".storysuitblaster"`, call `GameWorld.serverAddUpgrade(keeper.playerId + ".suitblaster", teamId)` for the team's keeper, guarded by `not GameWorld.boughtUpgrades.has(...)`. Use `upgradeBought` rather than `upgradeAdded`. Save loading replays upgrades through bare `addUpgrade`, which emits neither signal, and the blaster is restored from its own `BoughtUpgrades` entry.
3. Proxy display: give `storySuitblaster` the Suit Blaster's title, description and icon through translation keys (`upgrades.storysuitblaster.title`) and the tech icon lookup. The icon lookup isn't checked here; it's part of #12/#22.

If #19 decides on "base purchase plus upgrades that later gates need", the vanilla `suitblaster*` tree already covers radius, charges and speed. It only needs repricing, and maybe extra mod entries with `predecessors: [suitblaster]`. Those also follow the keeper gadget automatically through `followskeepergadget`.

**Alternatives**

- **Scripted grant without the shop**, for example as a story beat at a depth milestone: the same `serverAddUpgrade` call from mod code.
- **Guaranteed gadget chest:** in `prepareGameMode`, set `GameWorld.useCustomGadgetOrder = true` and `GameWorld.customGadgetOrder = ["suitblaster", ...]` (`GameWorld.gd:1431-1450`). The first chest then offers it through the vanilla popup. No money involved, so it doesn't fit the shop design, but it's zero-risk.
- **Proxy upgrade carrying `scenes: keepersuit: SuitBlaster.tscn` itself:** rejected. It skips slot bookkeeping, `addedGadgetIds` (so keeper respawn would lose it) and the vanilla upgrade tree.

## Risks and what Story Mode must handle

1. **Gadget chests.** If Story Mode keeps vanilla gadget chests, a chest can offer the Suit Blaster for free, or fill the keepersuit slot with a Probe, Prospection Meter or Resource Packer, which then blocks the purchase. Fix, set in Story Mode's `prepareGameMode`: `useCustomGadgetOrder = true` with a `customGadgetOrder` that leaves out all four keepersuit gadgets, or no chests at all (map archetype `gadget_*` fields). Note that a custom `modeId` falls into the `_:` branch of `prepareLevelStart` (`GameWorld.gd:335-336`) and never runs `prepareRegularLevelStart`, so nothing resets these flags after the mode sets them. This is part of the open "Vanilla systems in Story Mode" question on the map.
2. **Slot check.** Guard the grant with `GameWorld.areUpgradeSlotsAvailable` on the `asKeeperGadget`-modified data, or make the shop entry unbuyable while the slot is taken. Otherwise money is spent and the blaster is added on top of another suit gadget.
3. **Recharge is tied to wave timing.** Charge rate scales with `1 / getTimeBetweenWaves` and stops under `softPaused`. If the story text boxes or Story Mode's wave settings use soft pause or a very long wave interval, the blaster recharges slowly or not at all. Check this when #26 and the wave tuning land.
4. **Open tech tree doesn't show the new track** until it is reopened (see above). Cosmetic.
5. **Co-op prefixing.** The keepersuit id is per player (`playerN.suitblaster`). Story Mode is single-player, so granting for `Keepers.getAllOfTeam(teamId)` like the cheat menu is enough.

## Found along the way, for #20 (metal gate)

The Suit Blaster has no unique damage signature. `SuitblasterExplosion.explode` calls `Level.map.damageTileCircleArea` or `damageTileDirection` with `team1.suitblaster.damage = 5000` and passes no source. The same two functions are called by:

- Blast Mining mines (`Mine.gd:179-183`), also with damage 5000 (`blastMining.damage = 5000`)
- bomb caves (`CaveBomb.gd:130`, damage 10000)
- the Ninja keeper's Kunai (`Kunai.gd:448`, damage 1000)

`Map.damageTileCircleArea` (`Map.gd:1143`) only checks `Data.isDestructable(tile)`. A gate that "only the Suit Blaster breaks" can't be told apart by damage amount. Two options: tag the damage source (for example a script extension of `SuitblasterExplosion.gd` that sets a flag around the call, or one of `Map.gd`), or keep Blast Mining and bomb caves out of Story Mode.

## ModLoader notes

The recommended path needs no script extension and no hooks. It uses public signals (`GameWorld.upgradeBought`), the `gamemodes-prepare` group, and the mod's upgrade data. ModLoader 7.0.1 supports `ModLoaderMod.install_script_extension` and `install_script_hooks` (`addons/mod_loader/api/mod.gd:38`, `76`) if the tech-tree rebuild or the gate damage tag needs one. Hooks only fire in vanilla scripts that ModLoader's hook preprocessor has wrapped, so prefer script extensions on this decompiled project.
