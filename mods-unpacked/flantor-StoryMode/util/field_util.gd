extends RefCounted

# What the lava field (lava/lava_field.gd) and the gas field (gas/gas_field.gd)
# share.

const Story = preload("res://mods-unpacked/flantor-StoryMode/story.gd")

const KEEPER_BOX := Vector2(10, 16)


# The keeper's body, in world space: what lava and gas touch.
static func keeper_rect(keeper) -> Rect2:
	return Rect2(keeper.global_position - KEEPER_BOX * 0.5, KEEPER_BOX)


# A cell the player has revealed (vanilla keys visibleTileCoords by Vector2).
static func seen(map, c: Vector2i) -> bool:
	return map.visibleTileCoords.has(Vector2(c))


# A saved per-keeper value (playerId -> float, #231) under `key`; a save from
# before has the first local keeper's alone under `old_key`.
static func per_player(d: Dictionary, key: String, old_key: String) -> Dictionary:
	var out: Dictionary = {}
	var v = d.get(key, {})
	if v is Dictionary and not v.is_empty():
		for pid in v:
			out[str(pid)] = float(v[pid])
	else:
		out[Story.local_pid()] = float(d.get(old_key, 0.0))
	return out


# A suit bar at `p` (the canvas item's space), `share` full; white on `blink`.
static func draw_bar(ci: CanvasItem, p: Vector2, share: float, col: Color, blink: bool) -> void:
	ci.draw_rect(Rect2(p - Vector2(1, 1), Vector2(20, 5)), Color(0, 0, 0, 0.8))
	ci.draw_rect(Rect2(p, Vector2(round(18.0 * share), 3)), Color.WHITE if blink else col)
