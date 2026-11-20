// What the gas shaders share (#203).

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

// A 4x4 ordered dither threshold, 0..1, for stepped shades that sit with the pixel art.
float bayer(vec2 p) {
	int x = int(mod(p.x, 4.0));
	int y = int(mod(p.y, 4.0));
	int m[16] = int[16](0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5);
	return (float(m[y * 4 + x]) + 0.5) / 16.0;
}

// dot(tile, pick) blended between the four nearest tiles of `grid` (r open,
// g gas / 4, a fire), open ones only, so nothing shows through a wall.
float open_mix(sampler2D grid, vec2 uv, vec4 pick) {
	vec2 ts = vec2(textureSize(grid, 0));
	vec2 p = uv * ts - 0.5;
	vec2 i = floor(p);
	vec2 f = p - i;
	float sum = 0.0;
	float wsum = 0.0;
	for (int y = 0; y < 2; y++) {
		for (int x = 0; x < 2; x++) {
			vec4 t = texture(grid, (i + vec2(float(x), float(y)) + 0.5) / ts);
			float w = (x == 0 ? 1.0 - f.x : f.x) * (y == 0 ? 1.0 - f.y : f.y) * step(0.5, t.r);
			sum += dot(t, pick) * w;
			wsum += w;
		}
	}
	return wsum > 0.0 ? sum / wsum : 0.0;
}
