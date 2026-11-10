// PROTOTYPE: ruby drop, star shape, colors from palette/mineral_cells.json
var c = canvas();
drawMineral(c.img, "star", MINERALS.ruby);
save(c.sprite, "proto_ruby");
