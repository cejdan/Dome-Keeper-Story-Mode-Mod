shader_type canvas_item;

// The toxin's vignette closing in on the screen (gas/toxin_fx.gd, #202).

uniform float amount;
uniform float pulse;

#include "res://mods-unpacked/flantor-StoryMode/gas/look/common.gdshaderinc"

void fragment() {
	// In blocks of 4 screen pixels, dithered in steps, to sit with the pixel art.
	vec2 cell = floor(FRAGCOORD.xy / 4.0);
	vec2 uv = cell * 4.0 * SCREEN_PIXEL_SIZE;
	vec2 p = uv - 0.5;
	p.x *= 1.25;
	float d = length(p) * 1.55;
	// The clear middle shrinks as the toxin builds; the edge wavers.
	float wob = 0.05 * sin(uv.y * 31.0 + TIME * 1.7) + 0.04 * sin(uv.x * 23.0 - TIME * 1.1);
	float edge = smoothstep(1.1 - 0.7 * amount, 1.45 - 0.45 * amount, d + wob * amount);
	float lvl = floor(edge * 4.0 + bayer(cell)) / 4.0;
	vec3 col = mix(vec3(0.10, 0.34, 0.06), vec3(0.40, 0.78, 0.12), pulse * 0.5);
	COLOR = vec4(col, lvl * (0.18 + 0.5 * amount) * step(0.001, amount));
}
