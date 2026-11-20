extends RefCounted

# Loads the mod's PNGs straight from their bytes, so they need no Godot import
# step (the art folder is .gdignore'd). Textures are cached by path.

static var _cache: Dictionary = {}


static func tex(path: String) -> Texture2D:
	if _cache.has(path):
		return _cache[path]
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(path)
	if bytes.is_empty():
		push_error("StoryMode: missing art file " + path)
		return null
	var img: Image = Image.new()
	var err: int = img.load_png_from_buffer(bytes)
	if err != OK:
		push_error("StoryMode: bad PNG " + path)
		return null
	var t: ImageTexture = ImageTexture.create_from_image(img)
	_cache[path] = t
	return t


static func image(path: String) -> Image:
	var t: Texture2D = tex(path)
	return t.get_image() if t != null else null


# Makes `load(vanilla_path)` return the mod's texture. The cache keeps it alive.
static func provide(mod_path: String, vanilla_path: String) -> void:
	var t: Texture2D = tex(mod_path)
	if t != null:
		t.take_over_path(vanilla_path)
