# First new mineral end to end: bronze from tile to dollars

Type: task (AFK)
Status: open
Blocked by: 09, 10

## Question

Add bronze as a real mineral in Story Mode: it generates in the map, has its own tile and drop sprite (from the art pipeline in `art/`: square shape, locked colors from `art/palette/mineral_cells.json`), can be carried and delivered, and pays its dollar value. Pick the approach (new tile ID or graded ore) from ticket 09's findings, and record why on this ticket.

## Done when

- Harness: a revealed-map screenshot shows bronze tiles; mining and delivering one adds its value.
- A save made with bronze on the map loads back with bronze intact.
- The mod fills its palette cells at runtime (extension of `Style.gd`), and bronze looks the same under at least three different world palettes in a harness screenshot.
- Vanilla modes generate no bronze.
