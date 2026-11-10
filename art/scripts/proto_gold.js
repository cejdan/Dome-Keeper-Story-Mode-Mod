// PROTOTYPE: gold drop, square shape, colors from palette/mineral_cells.json
var c = canvas();
drawMineral(c.img, "square", MINERALS.gold);
save(c.sprite, "proto_gold");
