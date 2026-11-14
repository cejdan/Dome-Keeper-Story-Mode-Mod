extends RefCounted

# The monsters' runes (#92): a letter cipher and the translation stages.
#
# Each letter has one rune (art/runes/runes.png, drawn by
# art/tools/make_rune_font.py). Runes sit at Private Use Area codepoints, so a
# runed word holds no Latin letters; the rune font falls back to the game font
# for spaces, digits and English words, so one label shows both.
#
# Translation stage = translators installed (0..3): how much of a plea shows in
# English. 0: all runes. 1: the key words (*marked* in data/pleas.gd) plus
# English up to about a third of the words. 2: about two thirds. 3: all English.
# Beyond the key words, words translate in a fixed per-line order, so a line
# looks the same every time at a given stage.

const Assets = preload("res://mods-unpacked/cejdan-StoryMode/util/assets.gd")

const DIR := "res://mods-unpacked/cejdan-StoryMode/art/runes/"
const STAGE_KEY := "team1.story.translation"
const SHARE := [0.0, 1.0 / 3.0, 2.0 / 3.0, 1.0]
# Atlas pixels are scaled up by this before they become font glyphs.
const SCALE := 2

static var _font: FontFile = null
static var _meta: Dictionary = {}
static var _decode: Dictionary = {}


static func meta() -> Dictionary:
	if _meta.is_empty():
		var f: FileAccess = FileAccess.open(DIR + "runes.json", FileAccess.READ)
		if f != null:
			_meta = JSON.parse_string(f.get_as_text())
			for l: String in _meta.get("letters", {}):
				_decode[int(_meta["letters"][l]["code"])] = l
	return _meta


static func stage() -> int:
	return clampi(int(Data.ofOr(STAGE_KEY, 0)), 0, 3)


# Called when a translator is installed (#93).
static func set_stage(n: int) -> void:
	Data.apply(STAGE_KEY, clampi(n, 0, 3))


static func code_of(letter: String) -> int:
	var l: Dictionary = meta().get("letters", {}).get(letter.to_lower(), {})
	return int(l.get("code", 0))


# A word written in runes (letters only; anything else stays as it is).
static func runify(word: String) -> String:
	var out: String = ""
	for ch: String in word:
		var c: int = code_of(ch)
		out += char(c) if c != 0 else ch
	return out


# Runes back to letters, through the key: what a sharp player would do.
static func decode(s: String) -> String:
	meta()
	var out: String = ""
	for i in s.length():
		var c: int = s.unicode_at(i)
		out += _decode.get(c, s[i])
	return out


# The line at a translation stage, as plain text for a label using font().
# Key words that show in English come back highlighted when `bbcode`.
static func render(line: String, at_stage: int, bbcode: bool = false) -> String:
	var re: RegEx = RegEx.new()
	re.compile("(\\*?)([A-Za-z']+)(\\*?)")
	var words: Array = []
	for m: RegExMatch in re.search_all(line):
		words.append({"start": m.get_start(), "end": m.get_end(), "word": m.get_string(2), "key": m.get_string(1) == "*" or m.get_string(3) == "*"})
	var english: Dictionary = {}
	if at_stage >= 3:
		for i in words.size():
			english[i] = true
	elif at_stage >= 1:
		var keys: int = 0
		for i in words.size():
			if words[i]["key"]:
				english[i] = true
				keys += 1
		var want: int = int(round(SHARE[at_stage] * words.size()))
		var rest: Array = []
		for i in words.size():
			if not words[i]["key"]:
				rest.append(i)
		rest.sort_custom(func(a, b): return hash(line + str(a)) < hash(line + str(b)))
		for i in rest.slice(0, maxi(0, want - keys)):
			english[i] = true
	var out: String = ""
	var at: int = 0
	for i in words.size():
		var w: Dictionary = words[i]
		out += _esc(line.substr(at, w["start"] - at), bbcode)
		var text: String = w["word"]
		if english.has(i):
			out += ("[color=#ffe2d6]" + text + "[/color]") if bbcode and w["key"] else text
		else:
			out += runify(text)
		at = w["end"]
	out += _esc(line.substr(at), bbcode)
	return out


static func _esc(s: String, bbcode: bool) -> String:
	return s.replace("[", "[lb]") if bbcode else s


# The rune font: a bitmap font built from the atlas at the first call, with the
# game's large font as fallback for everything that isn't a rune.
static func font() -> FontFile:
	if _font != null:
		return _font
	var m: Dictionary = meta()
	var img: Image = Assets.image(DIR + "runes.png")
	if img == null or m.is_empty():
		return null
	img = img.duplicate()
	img.convert(Image.FORMAT_RGBA8)
	img.resize(img.get_width() * SCALE, img.get_height() * SCALE, Image.INTERPOLATE_NEAREST)
	var cell: Vector2 = Vector2(m["cell"][0], m["cell"][1]) * SCALE
	var size: int = int(cell.y)
	var cache: Vector2i = Vector2i(size, 0)
	var f: FontFile = FontFile.new()
	f.fixed_size = size
	f.fixed_size_scale_mode = TextServer.FIXED_SIZE_SCALE_ENABLED
	f.antialiasing = TextServer.FONT_ANTIALIASING_NONE
	f.set_texture_image(0, cache, 0, img)
	var ascent: float = size * 0.8
	f.set_cache_ascent(0, size, ascent)
	f.set_cache_descent(0, size, size - ascent)
	for l: String in m["letters"]:
		var e: Dictionary = m["letters"][l]
		var g: int = int(e["code"])
		var x: float = int(e["cell"]) * cell.x
		f.set_glyph_advance(0, size, g, Vector2(cell.x, 0))
		f.set_glyph_offset(0, cache, g, Vector2(0, -ascent))
		f.set_glyph_size(0, cache, g, cell)
		f.set_glyph_uv_rect(0, cache, g, Rect2(x, 0, cell.x, cell.y))
		f.set_glyph_texture_idx(0, cache, g, 0)
	f.fallbacks = [load("res://gui/fonts/FontLarge.tres")]
	_font = f
	return f
