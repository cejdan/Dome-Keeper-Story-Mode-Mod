// Gold nugget drop, 8x8 (same size as content/drop/iron/iron_smol.png).
// Structure copies the vanilla drops: bright outer ring, dark inner ring, lit core.
var c = canvas();
drawMap(c.img, [
  "..MMMM..",
  ".MDDDDM.",
  "MDLHHCDM",
  "MDHCCCDM",
  "MDCCCSDM",
  "MDCSSSDM",
  ".MDDDDM.",
  "..MMMM.."
], {
  M: "#ffe77d", // outer ring: brightest yellow in the palette (row 11)
  D: "#01060a", // inner dark ring
  L: "#ffecd4", // glint
  H: "#ffc375", // light face
  C: "#ffb565", // core
  S: "#e77754"  // shade
});
save(c.sprite, "gold_drop");
