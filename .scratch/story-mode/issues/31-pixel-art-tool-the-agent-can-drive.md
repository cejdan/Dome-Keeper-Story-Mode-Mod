# Which pixel art tool will the agent use, and can it drive it?

Type: task (AFK)
Status: resolved
Blocked by: none

## Question

The mod needs new 2D sprites (minerals, the metal gate tile, HUD icons, text box art). Which open-source pixel art tool does the agent use to make them, and does it have the access to drive that tool without a human at the mouse?

Needs:

- Open source, installable on this Windows machine.
- Drivable by the agent: a command line or scripting API is best, since GUI-only tools mean slow, coarse computer-use clicking.
- Exports PNG at exact pixel sizes, with no smoothing, using the game's palette.
- Keeps an editable source file (layers, frames) for later revision by the agent or a human.

## Done when

- The tool is installed and the agent has made 3 test sprites with it, sized and colored to match vanilla sprites.
- The sprites have been checked by eye next to the vanilla sprites they sit beside in the game.
- The answer records the tool, how the agent drives it, its limits, and where the test sprites live.

## Answer

**LibreSprite v1.3** (open source, GPL, an Aseprite fork), portable build in `../tools/libresprite`. The agent drives it fully headless: `libresprite -b <blank template.png> --script <sprite>.js`, where the script draws with `putPixel` and saves an editable `.ase` plus a PNG. No GUI or computer use is needed. The pipeline and quirks are in `art/README.md`.

Test sprites, all drawn by LibreSprite scripts in `art/scripts/`:

- `gold_drop` (8x8) and `sapphire_drop` (8x8), sized like `iron_smol.png`
- `money_icon` (44x44), sized like the tech-tree icons

Sources in `art/src/`, game-ready PNGs in `art/export/game/`, previews in `art/preview/`.

Findings that shape later art work:

- **Vanilla sprites store palette indices, not colors.** The palette shader reads red as the palette column and blue as the row. `art/tools/palette_encode.py` converts real-color art to that format and verifies the round trip (0 mismatches on all three sprites).
- **Verified in the real engine.** `art/tools/engine_render/` drew the sprites through the game's own shader and palette in Godot 4.3.1; the result matches the preview (`art/preview/engine_render.png`).
- **Palette swaps can merge minerals.** Under `palette_2_1`, gold turns the same yellow as iron and sapphire the same teal as water. Silhouettes keep them apart (nugget vs square, rhombus vs circle), but color alone is not enough. Raised on the sprites ticket.
- **Map tiles use a different path.** Ore overlays come from `content/map/border/resources_sheet.png` (12x12 grid of 24x24 frames) through the map shaders, and rock tiles are yellow masks, not palette sprites. The metal gate tile needs its own look into that path.
- **Limit:** drawing is by pixel map or code. Fine for drops and icons; big pieces (text box frames, tile sets) are slower to author this way, and a human can refine any `.ase` in a GUI.

Resolved 2026-11-10.
