// PROTOTYPE: diamond drop, star shape, colors from palette/mineral_cells.json
var c = canvas();
drawMineral(c.img, "star", MINERALS.diamond);
save(c.sprite, "proto_diamond");
