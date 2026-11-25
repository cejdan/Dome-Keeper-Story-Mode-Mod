shader_type canvas_item;

// The lava ocean's plain cells (#347): full, bright lava that isn't falling
// (lava/lava_field.gd draws everything else). One rect over the whole ocean
// draws, in each cell the mask marks, what _draw_body() would: the body, its
// dark bottom third, and the four drifting crust plates and hot veins, from
// the same per-cell noise (worked out once on the CPU). The field still draws
// a surface cell's ripples, line and embers over it. Pixels snap to the
// game's pixels, as the field's rects do.

uniform sampler2D mask : filter_nearest, repeat_disable;     // r 1: this layer draws the cell
uniform sampler2D plate_x : filter_nearest, repeat_disable;  // plates 0..3: noise x TILE
uniform sampler2D plate_v : filter_nearest, repeat_disable;  // plates 0..3: drift, px a second
uniform sampler2D plate_y : filter_nearest, repeat_disable;  // plates 0..3: the plate's row
uniform vec2 origin;          // the ocean rect's top-left, in the field's space
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

void fragment() {
	vec2 p = local - origin;
	ivec2 cell = ivec2(floor(p / tile));
	if (texelFetch(mask, cell, 0).r < 0.5) {
		discard;
	}
	vec2 q = floor(p - vec2(cell) * tile);
	// The bottom floor(TILE x 0.35) px are darker.
	vec4 col = q.y >= tile - floor(tile * 0.35) ? col_deep : col_body;
	vec4 xs = texelFetch(plate_x, cell, 0);
	vec4 vs = texelFetch(plate_v, cell, 0);
	vec4 ys = texelFetch(plate_y, cell, 0);
	for (int i = 0; i < 4; i++) {
		float px = floor(mod(xs[i] + time * vs[i], tile - 4.0));
		bool hot = i == 0 || i == 2;
		vec2 size = hot ? vec2(4.0, 1.0) : vec2(3.0, 2.0);
		if (q.x >= px && q.x < px + size.x && q.y >= ys[i] && q.y < ys[i] + size.y) {
			col = hot ? col_hot : col_crust;
		}
	}
	COLOR = col;
}
