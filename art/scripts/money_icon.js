// Dollar coin tech-tree icon, 44x44 (same size as content/icons/*.png).
// Coin body is drawn procedurally (circle with rim, lit upper left, shaded lower right),
// the "$" glyph from a pixel map.
var c = canvas();
var img = c.img;
var cx = 21.5, cy = 21.5, R = 18;
var OUT = hex("#0a0a13"), RIM = hex("#a24e53"), FACE = hex("#ffc375"),
    LIT = hex("#ffd48e"), GLINT = hex("#ffecd6"), SHADE = hex("#f79c5e"), DEEP = hex("#e77754");

for (var y = 0; y < 44; y++) {
  for (var x = 0; x < 44; x++) {
    var dx = x - cx, dy = y - cy, d = Math.sqrt(dx * dx + dy * dy);
    if (d > R + 0.5) continue;
    var col;
    if (d > R - 1) col = OUT;
    else if (d > R - 3) col = (dx + dy > 4) ? DEEP : RIM;
    else if (d > R - 4) col = OUT;
    else {
      var light = -(dx + dy) / (2 * R); // +1 upper left, -1 lower right
      col = light > 0.35 ? LIT : (light < -0.3 ? SHADE : FACE);
    }
    img.putPixel(x, y, col);
  }
}
// rim glint, upper left
var glint = [[9, 10], [10, 9], [11, 8], [8, 12], [12, 7], [14, 6]];
for (var i = 0; i < glint.length; i++) img.putPixel(glint[i][0], glint[i][1], GLINT);

var dollar = [
  "....XX....",
  "..XXXXXX..",
  ".XXXXXXXX.",
  "XXX.XX.XXX",
  "XXX.XX....",
  "XXXXXX....",
  ".XXXXXXX..",
  "..XXXXXXX.",
  "....XXXXXX",
  "....XX.XXX",
  "XXX.XX.XXX",
  ".XXXXXXXX.",
  "..XXXXXX..",
  "....XX...."
];
drawMap(img, dollar, { X: "#e77754" }, 18, 16); // drop shadow
drawMap(img, dollar, { X: "#73374e" }, 17, 15); // glyph
save(c.sprite, "money_icon");
