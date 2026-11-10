// Shared helpers for LibreSprite batch scripts. Concatenated in front of each sprite script by tools/draw.sh.
// Colors are real colors taken from the game palette (systems/style/palettes/palette_1_1.png);
// tools/palette_encode.py converts them to the game's palette-index encoding afterwards.

function hex(h) {
  var r = parseInt(h.substr(1, 2), 16), g = parseInt(h.substr(3, 2), 16), b = parseInt(h.substr(5, 2), 16);
  return app.pixelColor.rgba(r, g, b, 255);
}

function canvas() {
  var s = app.activeSprite;
  if (!s) throw new Error("no active sprite: pass a blank template PNG before --script");
  var img = s.layer(0).cel(0).image;
  return { sprite: s, img: img };
}

// rows: array of equal-length strings; legend: char -> "#rrggbb"; "." is transparent.
function drawMap(img, rows, legend, ox, oy) {
  ox = ox || 0; oy = oy || 0;
  for (var y = 0; y < rows.length; y++) {
    for (var x = 0; x < rows[y].length; x++) {
      var ch = rows[y].charAt(x);
      if (ch === "." || ch === " ") continue;
      if (!legend[ch]) throw new Error("no color for '" + ch + "' at " + x + "," + y);
      img.putPixel(ox + x, oy + y, hex(legend[ch]));
    }
  }
}

function save(sprite, name) {
  var base = OUTDIR;
  sprite.layer(0).name = name;
  sprite.saveAs(base + "/src/" + name + ".ase", true);
  sprite.saveAs(base + "/export/real/" + name + ".png", true);
  console.log("saved " + name + " " + sprite.width + "x" + sprite.height);
}
