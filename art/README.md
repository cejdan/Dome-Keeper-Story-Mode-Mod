# Art pipeline

Sprites are drawn by script in **LibreSprite** (open source, GPL), encoded into the game's palette format, then checked by eye. Godot ignores this folder (`.gdignore`); finished sprites get copied into the mod.

## Steps

1. **Draw.** `art/tools/draw.sh <name> <size>` runs `art/scripts/<name>.js` in LibreSprite batch mode on a blank `art/templates/blank<size>.png`. It writes `art/src/<name>.ase` (editable source, layers kept) and `art/export/real/<name>.png` (real colors).
2. **Encode.** `python art/tools/palette_encode.py encode art/export/real/<name>.png art/export/game/<name>.png --rows 3,11,12` converts real colors to palette indices and fails on any color outside the palette. It decodes the result again and reports round-trip mismatches (must be 0).
3. **Preview.** `python art/tools/preview.py art/preview/<sheet>.png --vanilla <vanilla pngs> --new <game pngs> --palettes palette_1_1,palette_2_1` renders the sprites at 6x and true size, next to vanilla sprites, under each palette.
4. **Every palette.** `python art/tools/palette_grid.py <out.png> name=path.png ... | name=path.png` shows game-encoded sprites under all 22 in-game palettes plus a true-size strip.
5. **Engine check.** `art/tools/engine_render/` is a tiny Godot project that draws sprites through the game's real palette shader and saves a screenshot. Edit the paths in `main.gd`, then run the engine with `--path` pointed at the folder. The window size there is 640x360; widen it for big sprites.

Run all commands from the `Dome Keeper` folder.

## How the game's colors work

Sprites do not store real colors. `systems/style/materials/palette_swap_shader.gdshader` looks up each pixel in a palette texture: **red picks the column (R = column x 8), blue picks the row (B = row x 20)**, green is ignored by the shader. The palette is a 32 x 13 grid of 10 px cells: `systems/style/palettes/palette_1_1.png` (real colors), `index_palette.png` (the matching encoded colors). Vanilla drops use row 3, tech-tree icons row 12.

**Mod-owned colors.** Row 3 columns 14 to 31 (and other high columns in rows 0 to 8) are empty in every vanilla palette. The mod can fill them at runtime, so colors placed there never change between worlds. `art/palette/mineral_cells.json` lists the cells and colors; the encode and preview tools apply it, as the mod will. Mineral sprites (`art/scripts/proto_*.js`) read their colors from that file through `MINERALS` (injected by `draw.sh`). Metals use the `square` shape and gems the `star` shape from `art/scripts/shapes.js`. The full set is previewed in `art/preview/story_mode_minerals.png`.

A real color appears in several rows. The row matters when the game uses another palette (`palette_2_1` etc.), so keep a sprite's colors in the row family of its kind.

## LibreSprite notes (v1.3, `../tools/libresprite`)

- Needs an empty `libresprite.ini` next to the exe (portable mode), or every run crashes on exit with `Error saving file:`.
- In batch mode `app.activeImage` is null: use `app.activeSprite.layer(0).cel(0).image`.
- Templates must not end in a digit: LibreSprite opens `blank8.png` + `blank9.png` as a 2-frame sequence. Use `canvas_<size>px.png`.
- v1.3 has no `--set`; `draw.sh` injects `OUTDIR` into the script instead.
- Draw with `image.putPixel(x, y, app.pixelColor.rgba(r, g, b, a))`; `sprite.saveAs(path, true)` writes `.ase` or `.png` by extension. `console.log` prints to stdout.
- Drawing is pixel maps and code, not brush strokes. That suits small sprites; large art (text box frames, full tiles) is slower to author this way. A human can refine any `.ase` in the LibreSprite or Aseprite GUI.

## Mineral art (generated)

`python art/tools/make_mineral_art.py` writes every mineral's sprites, palette-encoded, straight into `mods-unpacked/cejdan-StoryMode/art/minerals/`: `drop_<m>.png`, `icon_<m>.png` (the drop at 3x) and `sheet_<m>.png` (the ore sheet a tile is drawn from). It also writes `art/preview/mineral_sheets.png` in real colors. Shapes and colors come from `SHAPES` in that script and `art/palette/mineral_cells.json`; change those and run it again.

An ore sheet uses vanilla's grid (12 x 12 cells of 24 px, as in `content/map/border/resources_sheet.png`): the border-overlay block sits at cols 0-3, rows 0-3 (vanilla's iron block recolored), and five tile frames sit at cols 0-4, row 5. The tile and border shaders only read the sprite's red and blue channels as palette indices, so a new tile look needs nothing more than a sheet in this layout.

The mod loads these PNGs from their bytes at runtime (`util/assets.gd`), so they need no Godot import; `mods-unpacked/cejdan-StoryMode/art/` is `.gdignore`'d. The palette cells are filled at runtime by `util/palette.gd`, which mirrors `mineral_cells.json`.
