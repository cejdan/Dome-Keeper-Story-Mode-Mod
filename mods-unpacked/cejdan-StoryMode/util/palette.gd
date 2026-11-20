extends RefCounted

# Mod-owned palette cells. The game colours sprites by looking pixels up in a
# 32 x 13 palette texture that changes with the world. A few cells are empty in
# every vanilla palette; the mod fills them with fixed colours, so minerals look
# the same in every world. Cells and colours mirror art/palette/mineral_cells.json.

const CELL := 10

# name: [row, first column, dark, mid, light]
const CELLS: Dictionary = {
	"iron": [3, 14, "#4a4c52", "#8d8f96", "#cfd0d4"],
	"bronze": [3, 17, "#4a2a1c", "#8c5a36", "#c99467"],
	"gold": [3, 20, "#9a6a10", "#e8b923", "#fff3a0"],
	"sapphire": [3, 23, "#17266e", "#2f62d8", "#a8ccff"],
	"emerald": [3, 26, "#0f4a2a", "#20a24e", "#9ef5b2"],
	"ruby": [3, 29, "#5e0a1e", "#d0213f", "#ff9aa8"],
	"diamond": [4, 18, "#6f8796", "#cfe9f5", "#ffffff"],
	"mythril": [4, 21, "#1c5a6a", "#49c6cf", "#d9fffb"],
	"unobtainium": [4, 24, "#3d0b6e", "#b440ff", "#f6d2ff"],
	"metal": [4, 27, "#2b3038", "#5d6673", "#a9b4c2"],
	# Story items (#93, #94): translator stone, its rune-eye, miner bones, data log.
	"translator": [0, 16, "#4a3a34", "#a8957c", "#e6dcc4"],
	"rune_eye": [0, 19, "#5c0b12", "#ff3b30", "#ffd0a0"],
	"bones": [0, 22, "#544a3e", "#b9ae97", "#f1e9d4"],
	"datalog": [0, 25, "#0c2a1e", "#2fbf78", "#c4ffdf"],
}

static var _patched: Texture2D = null


# Call every frame: when the game has switched to a palette the mod has not
# filled yet, fill it and hand it back to Style.
static func keep_filled() -> void:
	var current: Texture2D = Style.palette
	if current == null or current == _patched:
		return
	var img: Image = current.get_image()
	if img == null:
		return
	img = img.duplicate()
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	for name: String in CELLS:
		var c: Array = CELLS[name]
		for i in 3:
			img.fill_rect(Rect2i((int(c[1]) + i) * CELL, int(c[0]) * CELL, CELL, CELL), Color(c[2 + i]))
	_patched = ImageTexture.create_from_image(img)
	Style.setPaletteToImg(_patched)
