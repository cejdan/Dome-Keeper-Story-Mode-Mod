// PROTOTYPE: iron drop, square shape, colors from palette/mineral_cells.json
var c = canvas();
drawMineral(c.img, "square", MINERALS.iron);
save(c.sprite, "proto_iron");
