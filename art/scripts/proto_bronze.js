// PROTOTYPE: bronze drop, square shape, colors from palette/mineral_cells.json
var c = canvas();
drawMineral(c.img, "square", MINERALS.bronze);
save(c.sprite, "proto_bronze");
