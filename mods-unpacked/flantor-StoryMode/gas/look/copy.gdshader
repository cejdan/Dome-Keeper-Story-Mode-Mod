shader_type canvas_item;
render_mode blend_disabled;

// A simulated field's copy (gas/gas_look.gd): its last state, as it was.

void fragment() {
	COLOR = texture(TEXTURE, UV);
}
