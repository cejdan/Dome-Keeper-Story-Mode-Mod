extends RefCounted

# What the finale's monsters (boss/surface_tentacle.gd, eye_flyer.gd,
# great_eye.gd) share: their monster data, and the vanilla Monster body built
# in code. Each draws itself, so its sprite is one clear pixel (the Monster
# wants an animated sprite with the flash material).


static func register(tech: String, hp: float, tier: int, size) -> void:
	Data.apply(tech + ".health", hp)
	Data.apply(tech + ".tier", tier)
	Data.apply(tech + ".size", size)
	Data.apply(tech + ".fullstunthreshold", 100000.0)
	Data.apply(tech + ".stunpriority", 0)
	Data.apply(tech + ".minstunlevel", 0.85)


# A new monster running `script`, with `hitbox` as its shape, not yet in the
# tree. `uid` is its id in vanilla's monster synchronizer.
static func make(script: String, node_name: String, tech: String, uid: int, hitbox: Shape2D) -> Area2D:
	var m: Area2D = Area2D.new()
	m.set_script(load(script))
	m.name = node_name
	m.techId = tech
	m.teamId = "team1"
	m.seed_f = randf() * TAU
	m.collision_layer = 128
	m.collision_mask = 0
	m.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	m.add_to_group("monster")
	m.UID = uid
	var spr := AnimatedSprite2D.new()
	spr.name = "Sprite2D"
	var frames := SpriteFrames.new()
	var img := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	frames.add_frame("default", ImageTexture.create_from_image(img))
	spr.sprite_frames = frames
	spr.material = load("res://content/monster/FlashMaterial.tres")
	m.add_child(spr)
	m.sprite = spr
	var box := CollisionShape2D.new()
	box.name = "HitboxDefault"
	box.shape = hitbox
	m.add_child(box)
	return m
