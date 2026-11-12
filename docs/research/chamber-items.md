# Chambers and carried items: research for #90

Question ([#90](https://github.com/cejdan/Dome-Keeper-Story-Mode-Mod/issues/90)): how can the mod place a gadget-style chamber at a chosen depth, holding its own item that the keeper carries home? Also, do supplement chambers work in Story Mode today? This feeds [#93](https://github.com/cejdan/Dome-Keeper-Story-Mode-Mod/issues/93) (translator chambers), [#94](https://github.com/cejdan/Dome-Keeper-Story-Mode-Mod/issues/94) (miner bones) and [#98](https://github.com/cejdan/Dome-Keeper-Story-Mode-Mod/issues/98) (supplement chambers).

Sources: the decompiled game in this repo's parent checkout (paths below are relative to `Dome Keeper/`), read 2026-11-12. Mod code is at `mods-unpacked/cejdan-StoryMode/` on `main` @ 64cdc4f. The evidence for question 4 also includes a headless generation probe and the existing playtest logs (see "Method" at the end).

## 1. How vanilla places gadget chambers, and how the mod can place its own

### The vanilla pipeline (three stages)

1. **Generation writes tile ids.** `TileDataGenerator.generate_resources` runs `generate_gadget_chambers` → `generate_power_cores` → `generate_relics` after the iron clusters (`content/map/generation/TileDataGenerator.gd:176-187`). `generate_gadget_chambers` (`:640-686`) starts at `a.gadget_first_depth` and steps down by `a.gadget_depth_step`. At each step it picks a cell near the nearest iron tiles and writes `Data.TILE_GADGET` (3) into five cells, `origin + gadget_chamber_offset` (`:22`: `(0,0) (0,-1) (1,0) (0,1) (1,1)`), through `tryPlace` (`:565-592`). `tryPlace` refuses any cell already holding a special id 3..9 (`:569`) and copies one biome onto all five cells. Power cores do the same with id 7 (`:766-799`, same five offsets, `:791`).
2. **Landing turns tile clusters into placements.** After generation, `LandingStage.generate_landmark_data` calls `Map.generateChamberPlacements(tileData)` (`stages/landing/LandingStage.gd:409-410`). That function flood-fills each connected cluster of ids 3, 4, 6 and 7 (`content/map/Map.gd:1547-1553`, `:1592-1620`). It marks every visited cell `Data.TILE_DIRT_MARK_BLOCKED_FOR_CHAMBER` (11, `:1606`) and records the cluster's **top-left** cell under the tile id as key. Gift chambers are the one case with a string key (`"skin3"`, `"pet7"`), placed on a free 2x2 of plain rock in B4 to B6 (`:1570-1590`).
3. **Map start instances scenes.** `LevelStage` copies the placements into the map (`stages/level/LevelStage.gd:108`). `Map.init` loops over them: string keys go to `GiftChamber.tscn`, and integer keys go to `getSceneForTileType(int(id))` (`content/map/Map.gd:194-214`, `:1013-1020`; `TILE_GADGET` → `GadgetChamber.tscn`, `TILE_SUPPLEMENT` → `PowerCoreChamber.tscn`). `addChamber` (`:1022-1032`) calls `addLandmark`. That places the chamber at the top-left, sets each cell of the chamber's `TileCover` to `chamber.getTileType()`, and registers tile-destroyed and tile-revealed listeners (`:1058-1085`). In dev mode it prints `placed <Name> at <coord>` (`:1083-1084`).

Two details matter for a mod:

- **The chamber's shape comes from its scene's `TileCover`, not from the generator.** `Chamber.place` reads the TileCover's used cells into `tileCoords` (`content/map/chamber/Chamber.gd:97-103`). The gadget chamber's cover is a 2x2 block (`GadgetChamber.tscn:61`). The supplement chamber's cover is the full five-cell shape (`PowerCoreChamber.tscn`, `layer_0/tile_data`, cells (0,0) (0,1) (1,1) (0,2) (1,2)). For a gadget chamber, the generator's two bottom cells stay as id 11. Id 11 is not in `Data.TILE_ID_TO_STRING_MAP` (`systems/data/Data.gd:174-186`), so the map draws it as dirt (`Map.gd:762`). The 2x2 cover sits on the top of the five-cell shape.
- **`TILE_DIRT_MARK_BLOCKED_FOR_CHAMBER` is bookkeeping only.** Only the landing flood fill (`Map.gd:1606`) and the two-dome map merge (`TileDataGenerator.gd:1305`) write it. A mod never needs to set it.

### What Story Mode does today

`story_gen.after_resources` runs after all of vanilla's `generate_resources` (`mods-unpacked/cejdan-StoryMode/extensions/content/map/generation/TileDataGenerator.gd:8-11`). It calls `remove_gadget_chambers`, which turns ids 3, 4 and 6 back to plain rock (`map/story_gen.gd:259-266`). **It leaves supplement id 7 alone** (`:261` lists only gadget, relic and relic switch).

### Recommended: reuse the gadget tile id for translator chambers

Story Mode has no gadget chambers of its own any more, so a `TILE_GADGET` cluster on a Story Mode map can mean "translator chamber":

1. **Placement**: add a step `place_translators(map_data, rand)` to `story_gen.after_resources`. Run it after `remove_gadget_chambers` and `place_gate`, and before `place_metal` and `place_pools`. In biome indices 1, 3 and 5 (B2, B4, B6), it picks a seeded 2x2 block of plain rock (`TILE_DIRT_START`). Every cell within 1 tile of the block must be plain rock or a mineral: no gate or metal, no special id 3..9, no border, nothing open. It writes id 3 into the 2x2. The flood fill's top-left is then the block's top-left, which matches a 2x2 `TileCover` exactly, like `addGiftChamber` does (`Map.gd:1570-1590`).
   - Placing it before metal and pools means those steps keep clear of it without code changes: `place_metal` skips cells next to ids 3..9 (`story_gen.gd:188`, `:246-252`), and a pool cell must have only plain rock or minerals within `POOL_GAP` (`:158-173`).
   - Keep it off the gate. `addChamber` overwrites whatever is in its cover cells with the chamber tile type (`Map.gd:1030`), so a chamber touching the gate would punch a hole in it once opened. The gate is under B3 (`data/map_config.gd:7-8`), so the B4 translator sits just below it and is reached by blasting the gate, as the design intends.
2. **Scene**: the mod's `Map` extension overrides `getSceneForTileType`. When `Story.is_story()` and `tileType == Data.TILE_GADGET`, it returns the mod's `TranslatorChamber.tscn`. This works because `Map.init` calls it as an instance method (`Map.gd:209`). Everything else keeps `super`.
3. **What you get for free by keeping id 3**:
   - every vanilla rule that protects special tiles: `tryPlace` and `generate_holes` skip ids 3..9 (`TileDataGenerator.gd:569`, `:1000`), the gate moves special tiles (`story_gen.gd:14`, `:308-321`), `_near_special` covers them;
   - the special chamber-tile look and extra health (`content/map/tile/Tile.gd:72-75`);
   - the chamber break sound (`Map.gd:793-794`).

   A new tile id would need all of those added by hand. It would also need a hook into the static `generateChamberPlacements`, which only scans the four fixed ids. Avoid relying on a script extension to override a static function.
4. **Which translator**: in `place()` (or `_ready`), the chamber reads its biome with `Level.map.tileData.get_biomev(coord)` and maps 1/3/5 to translators 1/2/3. You could also export and serialize an index, as `GiftChamber` does with `giftType` (`content/map/chamber/gift/GiftChamber.gd:10-23`).
5. **Save/load**: chambers save with `meta.scenepath = scene_file_path` (`Chamber.gd:39-43`), and `SaveGame` reloads that exact scene (`game/SaveGame.gd:480-487`). A chamber scene under `mods-unpacked/` comes back as itself, with its state (`currentState`, tile cover).

Cleanup a builder will hit: `dev/scenarios/t51_gadget_shop.gd:33-37` checks for zero `TILE_GADGET` tiles. That check must change, for example to "no `GadgetChamber` nodes" or "exactly three translator chambers".

(Option not taken: setting `gadgets = 0` in `MapConfig.make_archetype` would stop vanilla from placing gadget chambers at all. That is cleaner, but it changes the generator's random sequence, so every seed's map changes and existing seed-based scenarios move. `remove_gadget_chambers` already does the job.)

## 2. How a chamber hands over its item, and how delivery is detected

### Chamber side

The `Chamber.gd` lifecycle is the same for gadget, supplement, relic and gift chambers:

- When a cover tile is revealed, the state goes from HIDDEN to REVEALED (`Chamber.gd:137-142`).
- Each cover tile destroyed clears a cell. When none are left, `onExcavated()` runs (`:105-111`). The gadget chamber then calls `open()` and plays its opening animation. When that ends, the state is OPEN (`gadget/GadgetChamber.gd:22-37`).
- **Usable** (`content/shared/Usable.tscn`/`.gd`) is the focus point: it adds the chamber to group `usables` (`Usable.gd:32-33`). When the keeper presses use, `Chamber.useHit` emits `hit` (`Chamber.gd:150-155`). `ChamberSynchronizer` relays it to the server and then calls `registerHit(playerId)` everywhere (`ChamberSynchronizer.gd:50-66`).
- `registerHit`: on the server, if `drop_type != ""`, it spawns that drop at the **GizmoSpawn** marker with `"carriers": [playerId]`, so the keeper is carrying it at once. Then the state goes to EMPTY and `onUsed()` runs (`Chamber.gd:157-170`). The gadget chamber sets `drop_type = "gadget"` (`GadgetChamber.tscn:29`), the supplement chamber `"powercore"`, the relic chamber `"relic"`.
- **ResourceGrabber** is the opposite direction: a chamber that *takes* a drop. The supplement chamber's grabber wants one `water` drop (`PowerCoreChamber.tscn`, `dropType = "water"`). Once fed (`content/shared/drops/ResourceGrabber.gd:23-39`), the chamber opens (`supplement/PowerCoreChamber.gd:63-76`). A translator chamber does not need a grabber.

A translator chamber is therefore `GadgetChamber` with its own art and `drop_type = "translator"`. If it needs no behaviour of its own, its script can be a copy of `GadgetChamber.gd` that returns `TILE_GADGET` from `getTileType()`.

### What the keeper carries: three delivery paths at the dome

Drops are `RigidBody2D` `Carryable`s (`content/shared/drops/Carryable.gd`) with `Drop.gd` on top. When a drop enters a drop point, the drop point asks the drop's `DropEnterTrigger` whether it is a given type (`content/shared/drops/DropEnterTrigger.gd:3-8`). If yes, the drop floats to the point (`Drop.floatToDropTarget`, `Drop.gd:114-122`), and `arrived()` runs on arrival (`:71-75`).

| Path | Drop types | Dome node | On arrival | How the game notices |
|---|---|---|---|---|
| Shredder | iron, water, sand, pack (`content/dome/shredder/Shredder.gd:127-133`) | `$Shredder` | `shred()` (`Drop.gd:182-217`) | `<team>.inventory.<drop.type>` +1 |
| ArtifactDropPoint | gadget, powercore (`content/dome/ArtifactDropPoint.gd:12-26`) | ArtifactDropPoint | `network_shred` (`:8-10`) | `Drop.deactivate` queues the gadget or supplement choice while the drop floats in (`Drop.gd:134-140`) |
| RelicDropPoint | relic (`content/dome/RelicDropPoint.gd:20-32`) | RelicDropPoint | `network_shrink` and the `relic_recovered` signal (`:12-14`) | `shrink()` credits `<team>.inventory.<drop.type>` +1 (`Drop.gd:171-172`); the dome shakes and plays its relic socket animation (`content/dome/Dome.gd:455-458`); Relic Hunt listens on `team1.inventory.relic` (`content/gamemode/relichunt/Relichunt.gd:16-17`, `:105-108`) |

The trigger answers for a type, but the credit always goes to the drop's **own** `type`. Story Mode minerals already rely on this: `StoryDropTrigger` answers yes to the shredder's "are you iron?" question, and the piece is credited as its own mineral (`drops/StoryDropTrigger.gd:1-14`). `Storymode.propertyChanged` then pays dollars (`gamemode/Storymode.gd:69-77`).

**Carry feel** comes from `carryableType`. Mineral drops are `"resource"`: `content/drop/MineralDrop.tscn:29` is a small piece carried in the tether bunch. Gadget, power core and relic drops are `"gadget"`: one big item, slower, with `additionalSlowdown` (`content/drop/gadget/GadgetDrop.tscn:29`, `relic/RelicDrop.tscn:127`, `powercore/PowerCoreDrop.tscn`). Keeper1, the only Story Mode keeper (`extensions/stages/loadout/MultiplayerloadoutStage.gd:9`), only grabs one `carryableType` per hold (`content/keeper/keeper1/Keeper1.gd:340-345`, `:370-375`).

### Recommendation

- **Translator**: a carried object like the relic, `carryableType = "gadget"`. Its scene is modelled on `RelicDrop.tscn`/`PowerCoreDrop.tscn`, with `type = "translator"`. Its trigger script answers yes to `getDeliverableDrop("relic")` (same trick as `StoryDropTrigger`). RelicDropPoint then floats it in and shrinks it, and `Drop.shrink` credits `team1.inventory.translator` +1. `Storymode.gd` listens on that key to raise the translation stage and play the horror's beat.
  - Side effect to check in the build: the dome's relic socket animation and sound play (`Dome.gd:455-458`). They may read well as "installing", or the mod's Dome extension can skip them.
  - Nothing relic-specific fires: Relic Hunt's logic lives in `Relichunt.gd`, which is not the Story Mode mode node, and `lastreliccarrier` is set only for type `relic` (`Drop.gd:141-142`).
  - Fallback if the animation is unwanted: answer `"gadget"` instead (ArtifactDropPoint, shredded). No choice popup opens, because `deactivate` checks the drop's own type (`Drop.gd:135`).
- **Miner bones**: a small piece like a mineral, reusing the StoryDrop path (next section).

## 3. Can `drops/StoryDrop.gd` carry a translator or bones? What a custom item needs

`StoryDrop.gd` extends `Drop.gd`. It loads its sprite from `art/minerals/drop_<type>.png` and swaps its `DropEnterTrigger` script for `StoryDropTrigger` (shredder as iron) (`drops/StoryDrop.gd:1-16`). Each mineral scene instances vanilla `MineralDrop.tscn` and sets `type` (`drops/gold_drop.tscn`).

- **Bones: yes, mostly.** A `minerbones_drop.tscn` built like the mineral scenes is carried and shredded like a mineral and credited to `team1.inventory.minerbones`. What it lacks is the dollars: `Storymode.propertyChanged` pays only `Minerals.is_mineral` types (`gamemode/Storymode.gd:72-77`), and the bones' value depends on the biome. Two working designs:
  - one drop type with a `value` field (recommended). The mod's `Map.destroyTile` spawns the bones itself through `Level.drops.network_spawn` (it returns the `Carryable`, `content/map/DropSynchronizer.gd:696-701`; vanilla `spawnDrop` returns nothing, `Map.gd:866-872`). It sets `value` from the data file by `tile.layer`. A `BonesDrop.gd extends StoryDrop.gd` pays `value` on the server in a `shred()` override, guarded by `absorbed` like vanilla (`Drop.gd:182-184`), and serializes `value`.
  - or eight drop types, one per biome (`minerbones1`..`8`), added to a value table that `propertyChanged` already reads. That means no runtime fields, but eight scenes.
- **Translator: technically yes, but don't.** Answering "iron" would shred it like ore, credit `inventory.translator`, and carry as a small `resource` piece. Use a gadget-type carry scene with the relic-point trigger (section 2).

A custom carried item needs:

1. **Scene**: a `RigidBody2D` root with a `Drop`-derived script, `type`, and groups `["carryable", "saveable"]`. Use vanilla drop collision layers (`collision_layer = 34`, `collision_mask = 522`). It needs:
   - `Sprite2D` as `dropSprite`;
   - for an artifact-style carry, `CarrySprite` and `FocusSprite` (`HighlightShader.tres`) set as `carry_sprite`/`focus_sprite`;
   - a `DropEnterTrigger` child and a `CollisionShape2D`, which `deactivate` uses (`Drop.gd:136`);
   - a `ShredParticles` node if it is shredded (`Drop.gd:199-205`);
   - copy the node list from `content/drop/powercore/PowerCoreDrop.tscn` (gadget carry) or `content/drop/MineralDrop.tscn` (resource carry).
2. **Registration at mod start**: `Data.DROP_TYPES.append(type)` and `Data.DROP_SCENES[type] = scene`, like `Minerals.register` (`data/minerals.gd:78-84`). The network spawn encodes the type as its index in `DROP_TYPES` and refuses unknown types (`DropSynchronizer.gd:720-723`, `:756-758`), so `Chamber.registerHit` can only spawn a registered `drop_type`. Optionally add `Data.DROP_ICONS[type]`.
3. **Save/load**: `SaveGame` serializes every node in group `saveable` (`game/SaveGame.gd:102-105`, `:780-795`) as kind `generic`, with `meta.filename = scene_file_path`, position and carriers (`Carryable.gd:181-205`). On load it re-instances that scene (`SaveGame.gd:503-527`). Mod scene paths therefore restore as long as registration ran first, which it does: mod init comes before any level. Extra fields such as the bones' `value` need `serialize`/`deserialize` overrides that call `super`. Run state such as the translation stage, used chambers and seen logs belongs in `Data` (team1.story.*). It is saved with the run, as `team1.story.pieces` and `team1.inventory.money` already are.
4. **Art**: placeholder sprites, loaded through `util/assets.gd` like the mineral drops.

For bones as a tile in the rock, the tile needs:
- a mod tile id (minerals use 40-47, `data/minerals.gd:17-27`), registered in `Data.TILE_ID_TO_STRING_MAP`;
- a sheet so it draws (`Minerals.sheet_for_type` pattern);
- the data log opened from the mod's existing `Map.revealTile` hook (`extensions/content/map/Map.gd:12-22`), guarded by a saved "seen" flag so a reload doesn't replay it;
- the drop spawned from the existing `destroyTile` hook (`:25-48`);
- adding the id to `_near_special` (`story_gen.gd:246-252`), or metal can wall it in. Pools already keep away from it (`_pool_cell_ok`, `:169-172`).

## 4. Do supplement chambers spawn and work in Story Mode today?

**They spawn, but only one per run in the dev profile, because of a vanilla cap and not because of the mod.**

- **The mod keeps them.** `remove_gadget_chambers` skips id 7 (`story_gen.gd:261`); the gate's KEEP_IDS includes 7 (`:14`); metal and pools keep clear of special tiles; minerals replace only iron and rock (`:331-333`).
- **Generation places 4.** A headless probe (Method, below) generated Story Mode maps through the mod's generator extension for six seeds (12345, 1001-1005). Every map had exactly 4 five-cell supplement clusters, roughly at y 22-26, 42-47, 63-70 and 86-92, in biome indices 1-5 (B2-B6). `Map.generateChamberPlacements` returned 4 placements under key 7 for each. Vanilla prestige-10k maps gave the same 4.
- **The game then places 1.** Every Story Mode playtest log under `playtest_out/` shows exactly one `placed PowerCoreChamber at ...` (for example `t43_story/godot.log:301`, seed 12345 at (15, 22) in B2), next to five `placed GadgetChamber` lines in the runs from before #51. The cause is in `GameWorld.prepareLevelStart`, which runs **after** the mode's `prepareGameMode` (`game/GameWorld.gd:340-341`): `mapArchetype.powercores = min(powercores, supplementMaxCount)` (`:353-363`). `supplementMaxCount` is 1, plus 1 for the `rewardweaponsupplements` assignment reward, 1 for `rewardkeepersupplements` and 5 for `rewardgadgetsupplements` (`:355-362`). The dev profile has none, so the cap is 1. A player with the weapon and gadget rewards gets min(4, 7) = 4. Vanilla Relic Hunt and Prestige are capped the same way, so one chamber is "unchanged from vanilla" for this profile.
- **The offer path works by code reading (not yet seen in game).**
  - The chamber opens when a water drop is carried into its ResourceGrabber (`PowerCoreChamber.gd:38-40`, `:63-76`; Story Mode keeps vanilla water). It then hands over a `powercore` drop.
  - At the dome, ArtifactDropPoint takes it, and `Drop.deactivate` calls `Level.stage.queueChoice("powercore", ...)` (`Drop.gd:134-140`).
  - The mod's `LevelStage` extension passes every non-gadget offer to vanilla: `startGadgetChoiceInput`, `generateOffers`, `remoteSetOffers` and `addGadgetUpgrade` all fall through to `super` when the offer type isn't `gadget` or no shop slot is open (`extensions/stages/level/LevelStage.gd:23-25`, `:49-59`, `:79-81`, `:107-110`).
  - Vanilla then builds supplement offers with `GameWorld.generateSupplements` (`stages/level/LevelStage.gd:721-723`, `game/GameWorld.gd:1466-1511`).
  - What's offered depends on the same rewards. Weapon supplements need limit `weaponsupplements` and gadget supplements need `gadgetsupplements` (`upgrades.yaml:3766-3777`). Dome and keeper supplements (for example `keeper1powerdrill`) need no reward, so the dev profile still has offers.
- **One risk to watch**: the gate runs along the B3/B4 boundary, and the second and third power cores land near it (y ≈ 45 and ≈ 65). `place_gate` moves a special tile it lands on to the nearest rock below the wall, **one cell at a time** (`story_gen.gd:305-321`). That could split a five-cell cluster, and a split leaves a misshapen chamber plus a stray one-cell "chamber". In the six probe seeds no cluster was split (all 4 clusters were 5 cells), but #98's 20-seed check should assert it.

## Recommended approach per build ticket

- **#93 translator chambers**
  - Placement and scene: a `place_translators` step in `story_gen` (B2/B4/B6, 2x2 of `TILE_GADGET` on plain rock with a 1-tile clear ring, after `place_gate` and before `place_metal`/`place_pools`), and a `Map.getSceneForTileType` override that returns `TranslatorChamber.tscn` for `TILE_GADGET` in Story Mode.
  - The chamber: a GadgetChamber copy with `drop_type = "translator"`.
  - The translator: a gadget-carry drop registered in `Data.DROP_TYPES`/`DROP_SCENES`. Its trigger answers "relic", so RelicDropPoint shrinks it into `team1.inventory.translator`, and `Storymode.gd` listens on that key for the stage and the beat.
  - Update `t51_gadget_shop`'s "zero gadget tiles" check.
- **#94 miner bones**
  - A mod tile id (one tile per biome) placed by a `story_gen` step and added to `_near_special`.
  - The log opens from the `Map.revealTile` hook (once, flag in Data).
  - The bones drop is spawned in `Map.destroyTile`. It is a StoryDrop-based mineral-style piece (shredder via "iron"); a `BonesDrop.gd` pays a serialized `value` (from the data file, by biome) in `shred()`.
- **#98 supplement chambers**
  - Nothing to restore: they already spawn and use vanilla's offer path.
  - The ticket's check "matching the archetype's power core setting" should read **min(archetype `powercores` = 4, vanilla's `supplementMaxCount`)**. That is 1 in the dev profile, so a 20-seed map check through the game counts 1 per map, while a raw generator check counts 4.
  - If the user wants 4 regardless of the player's rewards, that is a design change from vanilla. The mod could set `a.powercores` back in its `TileDataGenerator` extension for `story_map` archetypes, which runs after the cap.
  - Add a cluster-size check (all 5 cells, none touching the gate) and the harness offer check (feed water, carry the core home, pick a supplement).

## Method

- Code reading of the files cited above.
- Headless probe (not committed). A `SceneTree` script, run as `godot --headless --path "Dome Keeper" --script <probe>` with `override.cfg` in place (Sentry disabled per the log). It waited for autoloads, called each `mod_init` node's `modInit()` so the mod's script extensions are installed (as `GameWorld.gd:187-188` does), and then:
  - generated maps from `MapConfig.make_archetype()` and from vanilla `prestige-10k.tres`;
  - counted id-7 clusters and called `Map.generateChamberPlacements`.

  It bypasses `GameWorld.prepareLevelStart`, so it shows the uncapped count. With mod init applied, the Story Mode maps had 0 gadget tiles, confirming the story steps ran.
- The in-game count comes from the existing harness logs (`playtest_out/*/godot.log`, the `placed ...` lines `Map.gd:1084` prints in dev mode).
