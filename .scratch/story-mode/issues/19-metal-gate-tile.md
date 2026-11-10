# Metal gate tile that only explosions break

Type: task (AFK)
Status: open
Blocked by: 12

## Question

Add a metal tile type for Story Mode: a riveted steel look (placeholder fine), drill hits do nothing, Suit Blaster explosions break it. `Tile.gd` has `maxDamagePerHit` and a `destructable` flag to build on.

Art note: map tiles are not palette sprites. Ore overlays come from `content/map/border/resources_sheet.png` (24x24 frames) through the map shaders, and rock tiles are masks. Work out how a new tile look is fed to those shaders before drawing it (see the answer on the pixel art tool ticket).

## Done when

- Harness: drilling a metal tile for 10 seconds leaves it intact (screenshot plus tile health in the log).
- A Suit Blaster blast next to it breaks it (frame burst).
- It reads clearly as different from rock and from the indestructible border.
