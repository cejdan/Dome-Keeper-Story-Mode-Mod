shader_type canvas_item;
render_mode unshaded;

// The lair seal's energy over one chamber entry (#366, endgame/lair_seal.gd).
// Drawn on a rect `u_size` world pixels big, worked out per world pixel so it
// stays as chunky as the game's pixel art. `u_phase` 0 is the thick blue slab
// over the crust (a dome into the lava, a lip into the chamber), 1 the thin
// membrane on the chamber's top edge; `u_tint` blue to purple. The opening
// drives `u_crack` (cracks of light), `u_flash` and `u_agitate` (flicker,
// faster flow); `u_rip0..3` are ripples from touches (x, y in rect pixels,
// age in s, strength; strength 0 = none).

uniform vec2 u_size = vec2(64.0, 62.0);
uniform vec4 u_hole = vec4(8.0, 56.0, 24.0, 48.0);   // x0, x1, crust top, crust bottom
uniform float u_cap = 18.0;
uniform float u_cap_edge = 4.0;
uniform float u_lip = 8.0;
uniform float u_over = 3.0;
uniform float u_membrane = 3.0;
uniform float u_phase = 0.0;
uniform float u_tint = 0.0;
uniform float u_crack = 0.0;
uniform float u_flash = 0.0;
uniform float u_agitate = 0.0;
uniform float u_time = 0.0;
uniform float u_seed = 0.0;
uniform float u_rip_life = 0.6;
uniform vec4 u_rip0 = vec4(0.0);
uniform vec4 u_rip1 = vec4(0.0);
uniform vec4 u_rip2 = vec4(0.0);
uniform vec4 u_rip3 = vec4(0.0);
uniform vec3 deep_a : source_color = vec3(0.055, 0.165, 0.62);
uniform vec3 mid_a : source_color = vec3(0.18, 0.43, 1.0);
uniform vec3 light_a : source_color = vec3(0.62, 0.85, 1.0);
uniform vec3 spark_a : source_color = vec3(0.92, 0.97, 1.0);
uniform vec3 deep_b : source_color = vec3(0.18, 0.12, 0.56);
uniform vec3 mid_b : source_color = vec3(0.42, 0.36, 1.0);
uniform vec3 light_b : source_color = vec3(0.72, 0.69, 1.0);
uniform vec3 spark_b : source_color = vec3(0.93, 0.92, 1.0);

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7)) + u_seed * 17.31) * 43758.5453);
}

vec2 hash2(vec2 p) {
	return fract(sin(vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3))) + u_seed) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
	float s = 0.0;
	float a = 0.5;
	for (int i = 0; i < 3; i++) {
		s += a * vnoise(p);
		p *= 2.03;
		a *= 0.5;
	}
	return s;
}

// Distance between the nearest two cell points: small on the cells' edges.
float voronoi_edge(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float d1 = 8.0;
	float d2 = 8.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 g = vec2(float(x), float(y));
			vec2 r = g + hash2(i + g) - f;
			float d = dot(r, r);
			if (d < d1) {
				d2 = d1;
				d1 = d;
			} else if (d < d2) {
				d2 = d;
			}
		}
	}
	return sqrt(d2) - sqrt(d1);
}

float ripple(vec4 r, vec2 p) {
	if (r.w <= 0.0 || r.z < 0.0 || r.z > u_rip_life) {
		return 0.0;
	}
	float k = r.z / u_rip_life;
	float d = length(p - r.xy);
	float ring = 1.0 - smoothstep(0.0, 1.6, abs(d - (4.0 + 62.0 * k)));
	float spot = (1.0 - smoothstep(0.0, 6.0, d)) * (1.0 - k) * (1.0 - k);
	return (ring * (1.0 - k) + spot) * r.w;
}

void fragment() {
	vec2 p = floor(UV * u_size) + 0.5;
	float ph = clamp(u_phase, 0.0, 1.0);
	float cx = (u_hole.x + u_hole.y) * 0.5;
	float hw_m = (u_hole.y - u_hole.x) * 0.5;
	float hw_s = hw_m + u_over;
	float hw = mix(hw_s, hw_m, ph);
	float dx = (p.x - cx) / hw_s;
	float dome = sqrt(max(0.0, 1.0 - dx * dx));
	float tq = floor(u_time * 30.0);
	float jit = u_agitate * (hash(vec2(tq, floor(p.x / 3.0))) - 0.5) * 3.0;
	float top_s = u_hole.z - u_cap_edge - (u_cap - u_cap_edge) * dome;
	float bot_s = u_hole.w + u_lip * (0.55 + 0.45 * dome);
	float top_m = u_hole.w - u_membrane;
	float bot_m = u_hole.w + u_membrane;
	float top = mix(top_s, top_m, ph) + jit;
	float bot = mix(bot_s, bot_m, ph);
	// The surface breathes.
	top += sin(p.x * 0.33 + u_time * 3.1) * mix(1.0, 0.5, ph);
	bot += sin(p.x * 0.27 - u_time * 2.3) * mix(0.6, 0.4, ph);
	float e = min(min(p.y - top, bot - p.y), hw - abs(p.x - cx));
	if (e < 0.0) {
		COLOR = vec4(0.0);
	} else {
		vec3 deep = mix(deep_a, deep_b, u_tint);
		vec3 mid = mix(mid_a, mid_b, u_tint);
		vec3 light = mix(light_a, light_b, u_tint);
		vec3 spark = mix(spark_a, spark_b, u_tint);
		float speed = 1.0 + 2.5 * u_agitate;
		// Energy welling up through it.
		float n = fbm(vec2(p.x * 0.09, p.y * 0.09 + u_time * 0.9 * speed));
		float n2 = fbm(vec2(p.x * 0.05 - u_time * 0.3 * speed, p.y * 0.12 - u_time * 0.5 * speed) + 7.0);
		float en = n * 0.65 + n2 * 0.5;
		vec3 col = mix(deep, mid, smoothstep(0.38, 0.9, en));
		// A lattice of light in the thick slab: the seal's weave.
		float l1 = abs(fract((p.x + p.y * 0.577) / 9.0 + u_time * 0.05) - 0.5);
		float l2 = abs(fract((p.x - p.y * 0.577) / 9.0 - u_time * 0.05) - 0.5);
		float lattice = clamp(step(l1, 0.06) + step(l2, 0.06), 0.0, 1.0);
		float weave = (1.0 - ph) * (0.3 + 0.3 * sin(u_time * 2.0 + p.x * 0.15 + p.y * 0.1));
		col = mix(col, light, lattice * weave * 0.55);
		// A bright core: the crust's middle, then the membrane's.
		float core_y = mix((u_hole.z + u_hole.w) * 0.5, u_hole.w, ph);
		float core = 1.0 - smoothstep(0.0, mix(2.4, 1.1, ph), abs(p.y - core_y + sin(p.x * 0.4 + u_time * 5.0) * 0.8));
		col = mix(col, light, core * 0.65);
		// The rim.
		float rim = 1.0 - smoothstep(0.0, 2.0, e);
		col = mix(col, light, rim * 0.85);
		if (e < 1.0) {
			col = mix(col, spark, 0.45);
		}
		// Glints.
		float g = step(0.986 - 0.02 * u_agitate, hash(floor(p) + vec2(floor(u_time * 12.0), 0.0)));
		col = mix(col, spark, g * 0.8);
		// Ripples from touches.
		float rp = ripple(u_rip0, p) + ripple(u_rip1, p) + ripple(u_rip2, p) + ripple(u_rip3, p);
		col = mix(col, spark, clamp(rp, 0.0, 1.0));
		// Cracks of white light, the opening's strain.
		float ce = voronoi_edge(p * 0.11 + vec2(u_seed * 3.7, 1.3));
		float crack = (1.0 - smoothstep(0.03, 0.1, ce)) * u_crack;
		col = mix(col, spark, crack);
		float flick = 1.0 + u_agitate * (hash(vec2(tq, 3.0)) - 0.5) * 0.7;
		col = mix(col * flick, vec3(1.0), clamp(u_flash, 0.0, 1.0));
		float a = mix(0.9, 0.94, ph) * (0.86 + 0.14 * en);
		a = max(a, max(rim, crack));
		COLOR = vec4(col, a);
	}
}
