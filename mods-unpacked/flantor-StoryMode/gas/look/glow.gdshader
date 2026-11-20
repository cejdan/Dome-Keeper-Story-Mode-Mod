shader_type canvas_item;
render_mode blend_add;

// The gas's sickly light on the rock around it (#203): the drawn density,
// blurred wide, added over everything the player has revealed.

uniform sampler2D dye : filter_linear, repeat_disable;
uniform sampler2D tiles : filter_nearest, repeat_disable;
uniform sampler2D tiles_soft : filter_linear, repeat_disable;   // the same texture, blended (for the fire's light)
uniform vec2 size_px;
uniform vec2 win_tiles;
uniform float time;
uniform float strength;

void fragment() {
	vec2 px = floor(UV * size_px / 2.0) * 2.0;
	vec2 uv = (px + 1.0) / size_px;
	if (texture(tiles, uv).b < 0.5) {
		COLOR = vec4(0.0);
	} else {
		float g = 0.0;
		float hot = 0.0;
		vec2 r = 1.0 / win_tiles;
		for (int i = 0; i < 12; i++) {
			float ang = float(i) * 0.5236;
			float rad = (i % 2 == 0) ? 0.55 : 1.25;
			vec2 at = uv + vec2(cos(ang), sin(ang)) * rad * r;
			g += min(texture(dye, at).x, 1.3);
			hot += texture(tiles_soft, at).a;
		}
		g = g / 12.0 + 0.5 * min(texture(dye, uv).x, 1.3);
		float flick = 0.9 + 0.1 * sin(time * 2.3 + px.x * 0.02);
		hot = hot / 12.0;
		float fl = 0.8 + 0.2 * sin(time * 31.0 + px.y * 0.05);
		COLOR = vec4(vec3(0.42, 1.0, 0.22) * g * strength * flick * (1.0 - min(1.0, hot * 2.0)) + vec3(1.0, 0.5, 0.12) * hot * 1.5 * fl, 1.0);
	}
}
