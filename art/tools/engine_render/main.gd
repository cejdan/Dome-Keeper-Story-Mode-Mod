extends Node2D

const GAME := "C:/Users/ncejd/Documents/dome_keeper_modding_v5.x/Dome Keeper"
const OUT := GAME + "/art/preview/engine_render.png"

func tex(path: String) -> ImageTexture:
	var img := Image.load_from_file(path)
	return ImageTexture.create_from_image(img)

func _ready() -> void:
	RenderingServer.set_default_clear_color(Color8(18, 18, 26))
	var shader := Shader.new()
	shader.code = FileAccess.get_file_as_string(GAME + "/systems/style/materials/palette_swap_shader.gdshader")
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("palette", tex(GAME + "/systems/style/palettes/palette_1_1.png"))
	var items := [
		["content/drop/iron/iron_smol.png", 6], ["content/drop/water/water_smol.png", 6], ["content/drop/sand/sand_smol.png", 6],
		["art/export/game/gold_drop.png", 6], ["art/export/game/sapphire_drop.png", 6],
		["content/icons/converterironduplication.png", 3], ["art/export/game/money_icon.png", 3]]
	var x := 40.0
	for it in items:
		var s := Sprite2D.new()
		s.texture = tex(GAME + "/" + it[0])
		s.material = mat
		s.centered = false
		s.scale = Vector2(it[1], it[1])
		s.position = Vector2(x, 120)
		add_child(s)
		x += s.texture.get_width() * it[1] + 20
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OUT)
	print("saved ", OUT)
	get_tree().quit()
