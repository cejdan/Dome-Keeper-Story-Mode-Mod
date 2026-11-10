# How does a mined resource travel from map generation to the inventory?

Type: research (AFK)
Status: open
Blocked by: none

## Question

Trace one iron tile through every system it touches, and list every place that hard-codes the three resource types, so ticket 12 can choose how new minerals are added.

Trace: `TileDataGenerator` (cluster placement, `adjust_ore_amounts`), `MapData`, `Map.revealTile` and `spawnDrop`, `Tile.setType` (sprites, health), drop scenes in `content/drop/`, carrying, dome delivery in `Drop.gd`, `inventory.<type>` in `Data`, the HUD inventory, `SaveGame` serialization, achievements, and drones and gadgets that read resource types.

Output: a list of files and functions with what each assumes, and a recommendation between new tile IDs per mineral and one ore tile with a per-tile grade.
