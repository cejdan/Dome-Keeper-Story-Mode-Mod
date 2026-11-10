// Shape families for mineral drops. Shape = kind of mineral, color = which one.
// Legend: M outer ring (mid), L light facet, C mid, S/D dark facet, K near-black (#12121a, constant in every palette).
var SHAPES = {
  // metals (bronze, iron, gold): vanilla-style square, 8x8, same footprint as iron_smol.png.
  // A rounded shape was tried and dropped: it reads too close to the round water drop.
  square: [
    "MMMMMMMM",
    "MKKKKKKM",
    "MKLLCCKM",
    "MKLCCCKM",
    "MKCCCDKM",
    "MKDDDDKM",
    "MKKKKKKM",
    "MMMMMMMM"
  ],
  // gems: four-point star, 9x9, same footprint as sand_smol.png
  star: [
    "....M....",
    "...MLM...",
    "...MLM...",
    ".MMLLDMM.",
    "MLLLLDDDM",
    ".MMLDDMM.",
    "...MDM...",
    "...MDM...",
    "....M...."
  ]
};

function drawMineral(img, shape, colors) {
  // colors: a MINERALS entry (from art/palette/mineral_cells.json) or a [dark, mid, light] array
  if (colors.colors) colors = colors.colors;
  drawMap(img, SHAPES[shape], { M: colors[1], L: colors[2], C: colors[1], D: colors[0], K: "#12121a" });
}
