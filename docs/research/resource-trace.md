# How a mined resource travels from map generation to the inventory

Research for issue #10, which feeds #13 (bronze end to end). Every claim cites the decompiled game source (Godot 4.3, read in the main checkout; paths are relative to the `Dome Keeper` project root, `file:line`) or the ModLoader addon shipped in `addons/mod_loader/`. Line numbers are from the decompiled files as they are on disk on 2026-11-10.

Vocabulary: the game calls cobalt `sand` everywhere in code (`CONST.SAND = "sand"`, `Data.TILE_SAND = 2`). "Type string" means the `"iron"`/`"water"`/`"sand"` names; "tile ID" means the integer stored in the map's resource layer.

## Recommendation

**Give each new mineral its own tile ID and type string (bronze = new ID + `"bronze"`), not one ore tile with a per-tile grade.**

Why:

1. **The pipeline is keyed on the type string end to end, and most of it is already generic.** `Drop.gd` credits `teamId + ".inventory." + type` (`content/drop/Drop.gd:172`, `:210`), floating/total counters use `"inventory.floating" + type` (`:39-40`), drop spawning looks the type up in `Data.DROP_TYPES`/`Data.DROP_SCENES` (`content/map/DropSynchronizer.gd:720`, `:757-758`), and `Data.values` is saved wholesale (`systems/data/Data.gd:1050-1051`). A new type string goes through all of that with no code change. A grade would have to be added to every one of those steps.
2. **A drop cannot carry per-instance data through spawning.** `_internal_network_spawn` encodes only type index, team, position, impulse and physics (`DropSynchronizer.gd:715-739`). The "initial data" flag is hard-coded `false` (`:737-738`). A graded drop would need extensions to the synchronizer, to `Drop.gd` (credit by grade, sprite by grade) and to drop save/load (drops are saved by `scene_file_path` only, `game/SaveGame.gd:786`, re-created from it at `:503-510`). With one scene per mineral, all of that comes for free.
3. **The map has no place to keep a grade.** `MapData` has exactly three layers: biome, hardness, resources (`content/map/MapData.gd:6-9`, `content/map/MapData.tscn`). A grade would need a fourth layer (and every layer copy, e.g. `MapData.stack` `:153-165`, `TileDataGenerator.merge_tiledata` `:1245+`, `MiningSummary`, ignores a fourth layer), or a value derived from coordinates. A new ID just uses the existing resource layer, and the packed `MapData` scene saves it with no extra code (`SaveGame.gd:174-176`, loaded `:381-383`).
4. **Vanilla modes stay untouched.** New IDs and type strings only show up on Story Mode maps, so every extension can be "handle my types, else `super()`". Re-using iron's ID would instead make every iron-specific vanilla rule apply to bronze, gold and the gems: wave/run start on `inventory.iron` (`content/monster/Monsters.gd:52`, `:82-84`), iron progress per layer (`content/map/Map.gd:188-192`, `:809-811`, `:1258-1267`), the first-iron-drop bonus (`Map.gd:838-842`), Extractor, ProspectionMeter, harmful iron and the converter. That is wrong for gems, which #14 made a separate family.
5. **It matches the #14 art decision.** Each mineral has its own locked colors and family shape, so it needs its own drop scene and tile frames either way. A grade would still need a texture swap per grade at runtime.

The one real cost of separate IDs is that every place that **lists** the three vanilla types has to learn the new ones (the "must touch" list below). That list is short and the same for every mineral. If bronze is written against a small mod-side mineral table (ID, type string, tile frame or texture, extra health, richness, drop scene, dollar value), gold through diamond become table rows plus sprites.

## The trace: one iron tile, step by step

### 1. Constants and registries

| Where | What it assumes |
|---|---|
| `systems/Const.gd:56-59` (autoload `CONST`) | `IRON/WATER/SAND` type strings are `const`. A mod can't add to them but doesn't need to: any literal string works as a type. |
| `systems/data/Data.gd:149-161` | Tile IDs are `const`: EMPTY -1, IRON 0, WATER 1, SAND 2, GADGET 3, RELIC 4, NEST 5, RELIC_SWITCH 6, SUPPLEMENT 7, CAVE 9, DIRT_START 10, DIRT_MARK_BLOCKED_FOR_CHAMBER 11, BORDER 19. |
| `Data.gd:174-185` `TILE_ID_TO_STRING_MAP` | Is a `var` dict, so a mod can add `{<id>: "bronze"}` at runtime. Unknown IDs fall back to `"dirt"` (`Map.gd:762`, `content/map/Tiles.gd` `change_tile_type`). |
| `Data.gd:38-55` `DROP_TYPES` | Is a `var` array, and its **index** goes over the wire as a `u8` (`DropSynchronizer.gd:720-725`). Appending at the end keeps vanilla indexes stable. |
| `Data.gd:57-74` `DROP_SCENES` | Is a `var` dict, type string to PackedScene. The mod adds `"bronze": BronzeDrop.tscn`. |
| `Data.gd:76-80` `DROP_ICONS` | Is a `var` dict with only the three resources. Used by UI icons; add an entry if a Story Mode HUD reads it. |

### 2. Map generation: `content/map/generation/TileDataGenerator.gd`

- Instanced from a `preload` in `stages/landing/LandingStage.gd:303`, `:329`, `:381`. Because the landing stage loads after ModLoader, a script extension of `TileDataGenerator.gd` takes effect (see the ModLoader section).
- `generate()` `:74-151` runs base shape, then biomes, hardness, border prepass, `generate_resources` (only if `a.generateResources`, `:131`), border, entrance.
- `generate_resources(rand)` `:162-208` fills all cells with DIRT_START (10), then: `generate_iron_clusters` `:594` (seeds `iron_cluster_rate`, then moves clusters apart), gadget chambers, power cores and relics (placed next to iron, `:659`, `:706`, `:772`), `adjust_ore_amounts` `:806-857`, `expand_iron_clusters` `:859-875` (grows each center to `iron_cluster_size_base + y * iron_cluster_size_per_y`), `generate_water` `:877`, `generate_cobalt` `:931` (note: it writes the literal `2` at `:978`), then `generate_holes` `:986`.
- `adjust_ore_amounts` hard-codes three per-biome lists (iron, water, sand) and three archetype rates (`iron_cluster_removal_rate`, `water_removal_rate`, `cobalt_removal_rate`).
- **ID-range assumptions**: `placeHole` treats `<= 2` (plus DIRT_START) as "ore or dirt a hole may eat", and re-scatters only IDs 0..2 (`:1101-1141`). `generate_holes` skips 3..9 (`:999`). `merge_tiledata` treats 3..9 as chambers (`:1286`). An ID outside 0..11 is neither ore nor chamber to these checks, so **place new minerals after `super.generate_resources()` returns** (after the holes) to avoid any interaction.
- Rates come from the `MapArchetype` resource (`a.*`, `content/map/generation/MapArchetype.gd`). A Story Mode mineral ladder can live in the mod's own table instead of new archetype fields.

### 3. Map storage: `content/map/MapData.gd` (a `TileMap`)

- The resource ID is stored as an atlas coordinate `(id % 10, id / 10)` on layer 2 (`:42-53`); `get_resource_cells_by_id` uses the same coding (`:88-89`).
- The tileset (`content/map/tileset.tres`) defines atlas cells for row 0 cols 0-8, row 1 cols 0,1,2,9, row 2 cols 0-5, and rows 3-8 (mostly complete). IDs 13-18 and 9 have **no** atlas cell. TILE_CAVE (9) is only ever compared, never written, so the game never shows whether an undefined coordinate survives `set_cell` and save. **Pick new IDs whose atlas cell exists**: 30-49 are fully defined (rows 3-4). Avoid 20, which `MiningSummary.gd:68`/`:100` uses as a "destroyed" marker. Suggested band: bronze = 40, then 41-49 for the rest of the ladder.
- `get_mineable_tile_coords` (`:103-113`) lists vanilla IDs only (used by probes/scanners). `get_remaining_mineable_tile_count` (`:99-101`) counts everything except BORDER, so the MINE_ALL achievement (`content/achievements/Achievement_MINE_ALL.gd`) counts new IDs automatically.
- Saved as a packed scene (`SaveGame.gd:174-176`) and reloaded (`:381-383`, `:424`): the raw ints persist, so **bronze tiles survive save/load with no extra code**.

### 4. Reveal: `Map.revealTile(coord)` (`content/map/Map.gd:732-782`)

- Reads the ID, creates a `Tile` from `tile_scene` (a runtime `load`, `:23`, so a `Tile.gd` extension applies), sets layer, biome, hardness, and `tile.type = TILE_ID_TO_STRING_MAP.get(id, "dirt")`.
- `match tile.type` (`:763-772`) sets `richness` from `map.ironrichness` / `map.cobaltrichness` / `map.waterrichness` and calls `revealTileVisually` (the rock-falloff mark) **only for the three resources**. A new type gets richness 0 and no visual reveal unless extended.
- `tilesByType` (`:83`, `:181`, `:775`) only tracks the three. Unused by bronze; harmless.
- `Map.init` (`:154-218`) counts iron per layer for `getProgress` (`:1258`); leave it iron-only.
- On load, `Map.deserialize` (`:1302-1352`) re-reveals saved tiles through the same `revealTile`, so an extended `revealTile` covers load too.

### 5. The tile: `content/map/tile/Tile.gd`

- `setType(type)` (`:42-117`) is a `match` with **no default branch**. Each resource sets `destructable`, picks a frame in `content/map/border/resources_sheet.png` (12x12 grid of 24px cells; iron `(2..6, 11)` random per coord, water `(2..3, 7)`, sand `(2, 3)`) and adds `map.<x>AdditionalHealth` (`properties.yaml:29-31`). An unknown type keeps `Tile.tscn`'s default frame 25 (a cobalt edge piece), gets **no** `destructable` meta (so `Data.isDestructable` is false, `Data.gd:1194`), and only base health. **Must be extended.**
- `serialize`/`deserialize` (`:269-306`) store the type string. They only run for damaged or overlaid tiles (`Map.gd:1284-1287`).
- `spawn_tile_break_particles` (`:253-267`) passes `type` to `TileBreakParticles`/`DirtParticle`, which pick iron/water/sand debris textures (`content/map/tile/DirtParticle.gd:13-22`). Unknown types use the default debris. Cosmetic.

### 6. Tile edges: `Map.updateBorderSprite` (`Map.gd:951-1008`)

- The colored edge overlay drawn around ore tiles loops over `[TILE_IRON, TILE_SAND, TILE_WATER]` (`:974`) and offsets frames by type (iron +8 rows, water +4, sand +0, `:992-996`) in the same `resources_sheet.png`.
- New IDs get no edge overlay. That is cosmetic, but the ore then looks pasted on. The vanilla sheet has exactly one free 4x4 block (cols 8-11, rows 8-11), so a second new mineral already won't fit. Plan a **mod-owned sheet per mineral** with the same 12x12 grid of 24px cells: tile frames plus a 4x4 edge block. Swap `res_sprite.texture` in the `setType` extension and `overlay.texture` in the border extension. The cracks shader takes `sheet_size = 12x12` (`content/map/tile/ResourceSprite.tscn`), so keep that grid.

### 7. Destroy and spawn drops: `Map.destroyTile` / `Map.spawnDrop` (`Map.gd:784-872`)

- Sound by type (`:786-804`, default = dirt sound). Iron layer count (`:809-811`).
- **Drops only for the three types** (`:835`): `drops = floor(goalRichness - 1 + randi() % 3)` with `goalRichness = richness * resourcemodifiers.richness.<type>`, plus a per-type running delta (`dropDeltas`, `:843-850`, saved at `:1290`), a cobalt pity rule, and a difficulty bonus. Then `spawnDrop` once per drop.
- `spawnDrop` (`:866-872`) builds `{type, position, impulse}` and calls `Level.drops.network_spawn` (`content/map/Drops.gd:44`) → `DropSynchronizer.network_spawn` (`:696`) → `_spawn_from_stream` instantiates `DROP_SCENES[DROP_TYPES[index]]` (`:750-788`).
- **Must be extended**: after `super.destroyTile(...)`, if the tile's type is a mod mineral, run the same drop count logic and call `spawnDrop`. `spawnDrop` itself is generic.

### 8. The drop scene: `content/drop/`

- `iron/IronDrop.tscn` inherits `MineralDrop.tscn`, sets `type = "iron"`, its own collision shapes, shred particles and bump sounds. `MineralDrop.tscn` carries `Drop.gd`, Sprite2D (`iron_smol.png`), CarrySprite (`carried.png`), FocusSprite (`icon_selector2.png`) and a `DropEnterTrigger`.
- Bronze = `BronzeDrop.tscn` in the mod, inheriting `MineralDrop.tscn` with `type = "bronze"` and the art-pipeline sprites. Groups `saveable` (for saves) and `drops` come from the scenes.
- `Drop._ready` (`Drop.gd:27-40`) bumps `inventory.floating<type>` and `inventory.total<type>`. These are generic, but `GameWorld.gd:682-717` only zeroes the vanilla keys per run. `Data.reset()` (`GameWorld.gd:646`, `Data.gd:666-670`) clears all values at run start anyway, so stale bronze counters don't carry over.

### 9. Carrying and delivery

- `content/keeper/Keeper.gd:253` sets the carried drop's target to `dome.getDropTarget(c.type)`. `content/dome/Dome.gd:228-245` `getDropTarget` is a `match` with iron/water/sand/pack mapped to `$Shredder`; **unknown types return null. Must be extended.**
- `content/dome/shredder/Shredder.gd:127-134` `_on_Shredder_area_entered` asks each entering area for `["iron", "water", "sand", "pack"]` only. **Must be extended** to include mod types. Dome 3 and 4 use subclasses that extend it by path (`content/dome/dome3/Shredder3.gd`, `content/dome/dome4/shredder/Shredder4.gd`). Since an extension takes over the path before those load, they inherit it.
- The shredder then calls `Level.drops.network_shred` (`Shredder.gd:94`) → `Drop.shred` (`Drop.gd:182-217`), or `Drop.shrink` for dome 3/4 (`:153-179`). Both do `Data.changeByInt(teamId + ".inventory." + type, 1)`. Generic: **bronze lands in `team1.inventory.bronze` for free.** `Data.changeByInt` defaults a missing key to 0 (`Data.gd:968-971`). `Data.of` on a missing key logs an error and returns -1 (`:672-677`), so the mod should `Data.apply("team1.inventory.bronze", 0)` at Story Mode run start, or read with `ofOr`.
- `Dome.propertyChanged` (`Dome.gd:178-182`) applies `harmfuldrops.<resource>` damage on any inventory gain. Generic, and inert without such a property.
- **Dollars**: nothing in vanilla turns inventory into money. #13's "pays its dollar value" is a Story Mode listener on `team1.inventory.<mineral>` (via `Data.listen`) or a `shred` extension, whichever the economy ticket settles.

### 10. HUD: `content/hud/inventory/Inventory.gd`

- Listens to exactly three keys and writes `LabelIron/LabelWater/LabelSand` (`:6-23`). New minerals need a Story Mode HUD element (wiki: *Adding HUD Elements*), not an edit to this one.

### 11. Save game: `game/SaveGame.gd`

- `Data.serialize()` (`:156`) saves every value, so `teamX.inventory.bronze` persists.
- The map tile data is a packed `MapData` scene (`:174-185`), so bronze IDs persist.
- `Map.serialize` (`Map.gd:1283-1300`) keeps `dropDeltas` (a dict keyed by type string, so it works for bronze), revealed coordinates and damaged-tile state.
- Drops are `saveable` nodes stored by `scene_file_path` (`:780-796`) and re-created with `load(...)` (`:503-510`). A mod drop scene path (`res://mods-unpacked/cejdan-StoryMode/...`) round-trips as long as the mod is loaded. A Story Mode save loaded without the mod would fail on those drops, which is acceptable.

### 12. Other readers of resource types (Story Mode scope decides which matter)

Listed for the "Vanilla systems in Story Mode" open question. Each one either ignores new types (harmless) or special-cases the three:

- Drones: `content/gadgets/droneyard/TransportDrone.gd:109-140`, `:258-295` and `Squidley.gd:105-136`, `:220-240`. Delivery is generic (`getDropTarget`, `inventory.<type>`), but the carried sprite is a `match` on the three types, so bronze would be carried invisibly. `DroneYard.gd:311` spends water.
- Gadgets: `teleporter/Teleporter.gd:295-298` (only the three plus pack teleport), `ressourcepacker/ResourcePackerEffect.gd:86` (packs only the three), `packeddrop/PackedDrop.gd` (generic by type string), `extractor/Extractor.gd` (iron only), `prospectionMeter/ProspectionMeter.gd` and `probe/ProbeMarker.gd` (vanilla IDs), `condenser/Condenser.gd` (water), `converter/*` (vanilla costs), `lift/Lift.gd:140-141` (iron and water from orbs), `furnace/*`, `mineraltree/*`, `orchard/Orchard.gd`, `shield/ShieldBattery.gd`, `repellent/Repellent.gd`.
- Keepers: `keeper3/Kunai.gd:283-340`, `:605` (reveal effects for the three IDs), `keeper4/Goblin*.gd` (uses the iron shredder position).
- Monsters: `content/monster/Monsters.gd:52`, `:82-84`. `runStarted` triggers on the first iron (it also triggers after 8 destroyed tiles, so this is harmless).
- Achievements: `Achievement_RESOURCES_COBALTSTACK.gd` and `Achievement_RESOURCES_COBALTRESCUE.gd` are cobalt-specific; `Achievement_MINE_ALL.gd` counts all non-border resource cells, so new IDs must be mined too for it to unlock.
- Summary/minimap: `content/gamemode/summary/MiningSummary.gd:455-475` colors vanilla IDs; unknown IDs show as stone.
- Tech tree and costs: `GameWorld.gd:950`, `:1016` and `TechTreePopup.gd` price upgrades in `inventory.<costType>`. Generic, so a Story Mode cost in bronze would work.
- Cheats and tools: `stages/level/Cheats.gd`, `systems/cheats/CheatDetection.gd`, `tool/*`. Not relevant.

## Touch-points for bronze (the "must touch" list)

Registration in `mod_main.gd` (runtime, no extension):
1. `Data.TILE_ID_TO_STRING_MAP[40] = "bronze"`
2. `Data.DROP_TYPES.append("bronze")` (end of array, u8 index)
3. `Data.DROP_SCENES["bronze"] = preload(".../BronzeDrop.tscn")` (and `DROP_ICONS` if used)

Script extensions, each "handle mod minerals, else `super()`":
4. `TileDataGenerator.gd`: `generate_resources` → `super`, then place bronze **only when the map is for Story Mode**.
5. `Map.gd`: `revealTile` (richness and visual reveal), `destroyTile` (drop count and `spawnDrop`), and optionally `updateBorderSprite` (edge overlay).
6. `Tile.gd`: `setType` (destructable, texture/frame, health).
7. `Dome.gd`: `getDropTarget` → `$Shredder`.
8. `Shredder.gd`: `_on_Shredder_area_entered` → also check mod types.

New files: `BronzeDrop.tscn` plus its sprites, a mineral sheet texture (tile frames and edge block), and a Story Mode HUD element. Palette cells via a `Style.gd` extension, as #14 decided.

Free (no work): drop spawn/sync, carry physics, `inventory.<type>` crediting, `Data` save/load, map tile save/load, `dropDeltas` save, drop save/load by scene path, MINE_ALL counting.

## ModLoader: extensions vs hooks (what's cheaper here)

- **Load order makes extensions safe for all of the above.** `ModLoader` is the 2nd autoload, before `CONST`, `Data`, `Level` and everything else (`project.godot` `[autoload]`). Its `_init` (`addons/mod_loader/mod_loader.gd:34`) loads mods, runs each `mod_main._init` (`_init_mod`, `:191`), then `_ModLoaderScriptExtension.handle_script_extensions()` (`:197`). So extensions are installed (via `take_over_path`, `addons/mod_loader/internal/script_extension.gd` `apply_extension`) before `Data.tscn` preloads the drop scenes, and long before `Map`, `Tile.tscn`, the dome and `TileDataGenerator.tscn` load.
- **Hooks don't work in our dev runs.** `install_script_hooks`/`add_hook` (`addons/mod_loader/api/mod.gd:76`, `:203`) need a preprocessed hook pack. That pack is only loaded when *not* in the editor (`mod_loader.gd:42-43`), and in the editor ModLoader only logs "No mod hooks .zip will be created when running from the editor" (`mod_loader.gd:215-218`). Our playtests run the editor binary (`CLAUDE.md`), so hooks would silently do nothing in the harness. **Use script extensions.**
- Extension caveats that apply here:
  - Wiki *Known Issues*, Preloads: once a script that `preload`s a scene is extended, the preloaded scene's own script can't be extended any more; the fix is to copy the scene and repoint. None of our targets hit this, because the extensions are installed before the preloading autoloads load.
  - Overrides must call `super(...)` to keep vanilla behavior (wiki *Extending Code*).
  - `static func`s (e.g. `Map.generateChamberPlacements`, `Tile.spawn_tile_break_particles`) are called on the class and are not a good override point. None of the must-touch points are static.
  - Autoload *constants* (`CONST.IRON`, `Data.TILE_IRON`) can't change, but the registries are `var`s and can be mutated from `mod_main`.
- `ModLoaderMod.extend_scene` (`mod.gd:290`) can edit a vanilla scene on load. It's an option for adding a HUD node to a vanilla HUD scene, but not needed for the pipeline.

## Newly sharp questions

- **Do undefined atlas coordinates survive?** Picking IDs 40-49 (defined atlas cells) sidesteps it. If #13 wants 13-18 instead, check in the engine that `set_cell` with an undefined atlas coordinate round-trips through `pack()` and save.
- **How does `TileDataGenerator` know it's generating for Story Mode?** It sees only the `MapArchetype` and seed (`init`, `:52-66`). Options: a Story Mode archetype `.tres` that the extension recognizes by `resource_path`, or a check on `Level.loadout.modeId`. This depends on how the mod-skeleton/game-mode ticket registers the mode.
- **Edge overlays need a bigger art deliverable than #14 listed.** Each mineral needs a 4x4 block of edge frames plus tile frames, not just "tile overlay, drop, carried, HUD icon". The vanilla sheet only has room for one more.
- **Dollar crediting point.** A listener on `inventory.<mineral>` (no extension needed) vs. a `Drop.shred`/`shrink` extension. That decision belongs to the economy ticket; #13 can use a listener.
- **Drop count per mineral.** `richness` and the drop-count formula are per type (`Map.gd:835-858`). Story Mode needs a richness value per mineral (a balance call; the default could match iron's 2).
