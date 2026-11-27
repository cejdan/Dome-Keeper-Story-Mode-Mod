shader_type canvas_item;
render_mode unshaded;

// The ship in the ocean and the coil round it (#368, endgame/ship.gd): under
// the lava's surface everything soaks to the scorched maroon of the ocean
// tentacles (map/tentacle_rig.gd), with a hot rim where the art drew its
// magenta rim marker, a bright collar right at the surface, and a fade into
// the deep. Above the lava it is tinted a little toward the lava's haze, so it
// reads as further back than the climbable tentacles.

uniform float lava_y = 0.0;              // world y of the lava's surface
uniform float soak_px = 30.0;
uniform float fade_from = 150.0;
uniform float fade_to = 330.0;
uniform vec4 depth_tint : source_color = vec4(0.55, 0.16, 0.10, 1.0);
uniform float depth_mix = 0.18;
uniform vec4 rim_col : source_color = vec4(1.0, 0.86, 0.45, 1.0);
uniform vec4 collar_col : source_color = vec4(1.0, 0.70, 0.25, 1.0);
uniform float fade_all = 1.0;            // 0..1, the whole thing (the placeholder sink)

varying float world_y;

void vertex() {
	world_y = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).y;
}

void fragment() {
	vec4 c = COLOR;
	float d = world_y - lava_y;
	float s = clamp(d / soak_px, 0.0, 1.0);
	bool rim = c.r > 0.95 && c.b > 0.95 && c.g < 0.05;
	if (rim) {
		c = vec4(rim_col.rgb, rim_col.a * s * c.a);
	} else {
		float lum = dot(c.rgb, vec3(0.3, 0.5, 0.2));
		vec3 soaked = mix(vec3(0.10, 0.02, 0.05), vec3(0.27, 0.06, 0.12), smoothstep(0.04, 0.28, lum));
		soaked = mix(soaked, vec3(0.58, 0.18, 0.10), smoothstep(0.38, 0.78, lum));
		vec3 dry = mix(c.rgb, depth_tint.rgb * (0.4 + lum), depth_mix);
		c.rgb = mix(dry, soaked, s);
		float collar = 1.0 - smoothstep(0.5, 2.5, abs(d));
		c.rgb = mix(c.rgb, collar_col.rgb, collar * 0.8);
	}
	c.a *= (1.0 - smoothstep(fade_from, fade_to, d)) * fade_all;
	COLOR = c;
}
