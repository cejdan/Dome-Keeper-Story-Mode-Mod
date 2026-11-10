# How do we get sprites for the new minerals and the metal gate tiles?

Type: grilling (HITL)
Status: resolved
Blocked by: 31

## Question

Who makes the art, and to what standard? Each mineral needs a tile overlay, a drop sprite, a carried sprite and a HUD icon; the gate needs a metal tile.

Options: recolors of vanilla iron and cobalt sprites (the wiki's Palette Recolor and Palette Swap pages), sprites the user draws, generated pixel art, or commissioned art. Placeholders can ship first and be replaced later.

What ticket 31 settled: the agent can make sprites itself with LibreSprite (scripted, palette-encoded, checked in the engine); see `art/README.md` and the three test sprites in `art/preview/`. Still open here:

- Is agent-made pixel art good enough for release, or a placeholder until a human artist takes over?
- Game palettes can recolor minerals into each other (gold looks like iron and sapphire like water under `palette_2_1`). Should Story Mode lock one palette, or must every mineral stay distinct under all palettes (shape, plus a tuned row per palette)?

## Answer

Decided by the user on 2026-11-10:

- **Colors are locked.** Every Story Mode mineral uses mod-owned palette cells (empty in every vanilla palette, filled by the mod at runtime), so it looks the same in every world. Cells and colors live in `art/palette/mineral_cells.json`.
- **Shape marks the family, color marks the mineral.** Metals (bronze, iron, gold) are the vanilla-style square. Gems (sapphire, emerald, ruby, diamond) are a four-point star. A rounded metal shape was tried and dropped because it reads like the round water drop. Water keeps its circle and cobalt its triangle.
- **Iron becomes grey metal.** In Story Mode the orange vanilla iron is replaced by a steel-grey square; the orange look is gone from the mod.
- **The agent makes the sprites** with the LibreSprite pipeline in `art/`. Whether that art is final or a placeholder for a human pass is left for later (map: Not yet specified).

Evidence: `art/preview/story_mode_minerals.png` (the full set under all 22 palettes and at true size).

## Comments

**2026-11-10, palette and shape prototype (agent).** Evidence: `art/preview/drops_all_palettes.png` (vanilla and first test sprites under all 21 in-game palettes) and `art/preview/proto_all_palettes.png` (locked-color prototypes under all 22 palettes).

- Vanilla colors shift per world (`properties.yaml` lists 7 worlds, 18 palettes). Iron shifts most (orange, yellow, green, teal, pink). Water is usually cool but goes green in 3_2, 6_6 and 7_2 and near-black in 4_1. Cobalt is usually pink or purple but goes brown or orange in 2_1, 3_2, 6_1, 6_6 and 7_2.
- Only 3 vanilla palette cells never change, and all are neutrals (near-white, light gray, near-black).
- **Row 3 columns 14 to 31 (18 cells) are empty in every palette**, and more free cells exist in rows 0 to 8. A mod can fill them at runtime by extending `Style.gd` where it builds the palette texture; colors there are then fixed in every world. The prototype fills them from `art/palette/mineral_cells.json`. That injection is simulated in the preview tools so far, not yet run in the engine.
- Prototype shapes: rounded nugget for metals (bronze, gold, 8x8), four-point star for gems (sapphire, emerald, ruby, diamond, 9x9), and vanilla iron's square re-colored into locked cells. All stay distinct in every palette.
- Vanilla iron turns yellow in several worlds (2_1, 5_1, 6_1, 6_3) and then sits close to gold. Locking iron's color in Story Mode avoids that.

Options for the user:

1. Lock every Story Mode mineral color (iron included) in mod-owned cells; shape marks the family only: square or nugget for metals, star for gems, one special shape for mythril and unobtainium. Water and cobalt keep their vanilla circle and triangle. (Agent's recommendation.)
2. Same mod-owned cells, but colors tuned per world to match each palette's mood. More art work, and every world must be checked for collisions.
3. Lock Story Mode to one palette. Simplest, but loses world variety.
