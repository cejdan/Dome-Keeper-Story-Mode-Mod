shader_type canvas_item;

// The green haze over the dome's inside as its gas builds (gas/dome_gas.gd, #213).

uniform float amount;

#include "res://mods-unpacked/cejdan-StoryMode/gas/look/common.gdshaderinc"

void fragment() {
	float inside = step(0.5, texture(TEXTURE, UV).a);
	// In 2-pixel blocks, dithered in steps, to sit with the pixel art.
	vec2 px = floor(UV / TEXTURE_PIXEL_SIZE / 2.0);
	vec2 q = px * 0.07;
	float n = 0.6 * noise(q + vec2(TIME * 0.11, -TIME * 0.19)) + 0.4 * noise(q * 2.3 + vec2(-TIME * 0.17, -TIME * 0.08));
	// Gas rises: thicker toward the top of the dome.
	float rise = 1.15 - 0.45 * UV.y;
	float d = clamp(amount * (0.5 + 0.6 * n) * rise, 0.0, 1.0);
	float lvl = floor(d * 6.0 + bayer(px)) / 6.0;
	vec3 col = mix(vec3(0.30, 0.56, 0.12), vec3(0.62, 0.86, 0.26), n);
	COLOR = vec4(col, inside * clamp(lvl * 0.9, 0.0, 0.88));
}
