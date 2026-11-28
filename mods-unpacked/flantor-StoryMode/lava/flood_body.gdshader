shader_type canvas_item;

// The flood line's implied lava (#369): every open cell the player has seen
// under the rising lava's band, down to the ocean (lava/lava_field.gd, "the
// flood line"). One rect over those rows draws, in each cell the mask marks,
// what the field draws for a full cell under more lava: the body, its dark
// bottom third, and four drifting crust plates and hot veins (as the ocean's
// plain cells, lava/ocean_body.gdshader), from a per-cell hash instead of a
// noise texture, so no cell is stored. Pixels snap to the game's pixels.

uniform sampler2D mask : filter_nearest, repeat_disable;  // r 1: implied lava here
uniform vec2 origin;          // the mask's cell (0, 0) top-left, in the field's space
uniform vec2 first_cell;      // the mask's cell (0, 0) in map cells
uniform float time;
uniform float tile = 24.0;
uniform vec4 col_body;
uniform vec4 col_deep;
uniform vec4 col_hot;
uniform vec4 col_crust;

varying vec2 local;

void vertex() {
	local = VERTEX;
}

// 0..1 from a map cell and an index.
float h(ivec2 c, int i) {
	uint x = uint(c.x + 32768) * 374761393u + uint(c.y + 32768) * 668265263u + uint(i) * 2246822519u;
	x = (x ^ (x >> 13u)) * 1274126177u;
	x = x ^ (x >> 16u);
	return float(x & 65535u) / 65536.0;
}

void fragment() {
	vec2 p = local - origin;
	ivec2 cell = ivec2(floor(p / tile));
	ivec2 size = textureSize(mask, 0);
	if (cell.x < 0 || cell.y < 0 || cell.x >= size.x || cell.y >= size.y || texelFetch(mask, cell, 0).r < 0.5) {
		discard;
	}
	vec2 q = floor(p - vec2(cell) * tile);
	vec4 col = q.y >= tile - floor(tile * 0.35) ? col_deep : col_body;
	ivec2 mc = cell + ivec2(first_cell);
	for (int i = 0; i < 4; i++) {
		float px = floor(mod(h(mc, i) * tile + time * (2.0 + 3.0 * h(mc, i + 5)), tile - 4.0));
		float py = 3.0 + floor(h(mc, i + 11) * (tile - 6.0));
		bool hot = i == 0 || i == 2;
		vec2 sz = hot ? vec2(4.0, 1.0) : vec2(3.0, 2.0);
		if (q.x >= px && q.x < px + sz.x && q.y >= py && q.y < py + sz.y) {
			col = hot ? col_hot : col_crust;
		}
	}
	COLOR = col;
}
