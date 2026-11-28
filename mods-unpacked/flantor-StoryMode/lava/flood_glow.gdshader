shader_type canvas_item;
render_mode blend_add;

// The flood line's implied lava's glow (#369): the light lava_field.gd's glow
// pass puts round each lava cell, for the cells lava/flood_body.gdshader
// draws (its mask), as one rect: each pixel adds the light of the masked
// cells within two cells of it (as lava/ocean_glow.gdshader does for the
// ocean).

uniform sampler2D mask : filter_nearest, repeat_disable;
uniform sampler2D glow_tex : filter_nearest, repeat_disable;  // the field's radial glow texture
uniform vec2 origin;          // the mask's cell (0, 0) top-left, field space
uniform vec2 first_cell;      // the mask's cell (0, 0) in map cells
uniform float time;
uniform float tile = 24.0;

varying vec2 local;

void vertex() {
	local = VERTEX;
}

void fragment() {
	vec2 p = local - origin;
	ivec2 here = ivec2(floor(p / tile));
	ivec2 size = textureSize(mask, 0);
	vec3 sum = vec3(0.0);
	for (int dy = -2; dy <= 2; dy++) {
		for (int dx = -2; dx <= 2; dx++) {
			ivec2 c = here + ivec2(dx, dy);
			if (c.x < 0 || c.y < 0 || c.x >= size.x || c.y >= size.y || texelFetch(mask, c, 0).r < 0.5) {
				continue;
			}
			vec2 centre = (vec2(c) + 0.5) * tile;
			vec2 uv = (p - centre) / 96.0 + 0.5;
			if (uv.x < 0.0 || uv.y < 0.0 || uv.x >= 1.0 || uv.y >= 1.0) {
				continue;
			}
			vec2 mc = first_cell + vec2(c);
			float flick = 0.85 + 0.15 * sin(time * 6.0 + mc.x * 2.1 + mc.y);
			vec4 t = texture(glow_tex, uv);
			sum += t.rgb * t.a * 0.22 * flick;
		}
	}
	if (sum.r + sum.g + sum.b <= 0.0) {
		discard;
	}
	COLOR = vec4(sum, 1.0);
}
