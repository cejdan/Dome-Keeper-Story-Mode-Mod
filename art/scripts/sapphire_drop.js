// Sapphire drop, 8x8. Rhombus silhouette so it never reads as the round water drop.
var c = canvas();
drawMap(c.img, [
  "...MM...",
  "..MDDM..",
  ".MDLFDM.",
  "MDLFFSDM",
  "MDFFSSDM",
  ".MDSSDM.",
  "..MDDM..",
  "...MM..."
], {
  M: "#779fc5", // outer ring, lighter than water's #48669e
  D: "#01060a", // inner dark ring
  L: "#f1f1ef", // glint
  F: "#3366a1", // face
  S: "#1c3165"  // shade
});
save(c.sprite, "sapphire_drop");
