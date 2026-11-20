shader_type canvas_item;
render_mode blend_disabled;

// The gas's velocity field (#203), one step at a time.
// State: xy velocity (texels a step / DT), z pressure density (rests at 1), w curl.
// A single-pass compressible solver: the density's gradient is the pressure.

uniform sampler2D prev : filter_linear, repeat_disable;
uniform sampler2D dye : filter_linear, repeat_disable;
uniform sampler2D tiles : filter_nearest, repeat_disable;   // r open, g gas / 4, b revealed
uniform sampler2D flux : filter_linear, repeat_disable;     // rg the grid's gas movement, 0.5 = none
uniform vec2 texel;          // 1 / field size
uniform vec2 shift;          // the window moved this frame (uv)
uniform vec2 origin;         // the window's corner in world texels
uniform float sub;           // texels per tile
uniform float run;           // 1 on a step, 0 to carry the state over
uniform float time;
uniform vec2 keeper;         // texels in the window
uniform vec2 keeper_vel;     // field velocity units
uniform float keeper_r;
uniform float buoyancy;
uniform float churn;
uniform float vorticity;
uniform float jet;
uniform float flux_gain;

const float DT = 0.15;
const float K = 0.2;
const float VISC = 0.3;

#include "res://mods-unpacked/flantor-StoryMode/gas/look/common.gdshaderinc"

bool solid(vec2 uv) {
	return texture(tiles, uv).r < 0.5;
}

// A swirling push with no sources or sinks: the curl of a noise field.
vec2 curl(vec2 p) {
	float e = 0.3;
	float n0 = noise(p);
	return vec2(noise(p + vec2(0.0, e)) - n0, -(noise(p + vec2(e, 0.0)) - n0)) / e;
}

// A neighbour's state; rock gives a still wall at this cell's own pressure.
vec4 at(vec2 uv_new, vec2 uv_old, vec4 c) {
	if (solid(uv_new)) {
		return vec4(0.0, 0.0, c.z, 0.0);
	}
	return texture(prev, uv_old);
}

void fragment() {
	vec2 old = UV + shift;
	if (solid(UV) || old.x < 0.0 || old.y < 0.0 || old.x > 1.0 || old.y > 1.0) {
		COLOR = vec4(0.0, 0.0, 1.0, 0.0);
	} else {
		vec4 data = texture(prev, old);
		if (run > 0.5) {
			vec2 ex = vec2(texel.x, 0.0);
			vec2 ey = vec2(0.0, texel.y);
			vec4 tr = at(UV + ex, old + ex, data);
			vec4 tl = at(UV - ex, old - ex, data);
			vec4 tu = at(UV + ey, old + ey, data);
			vec4 td = at(UV - ey, old - ey, data);
			vec3 dx = (tr.xyz - tl.xyz) * 0.5;
			vec3 dy = (tu.xyz - td.xyz) * 0.5;
			vec2 dens_dif = vec2(dx.z, dy.z);
			data.z -= DT * dot(vec3(dens_dif, dx.x + dy.y), data.xyz);
			vec2 lap = tu.xy + td.xy + tr.xy + tl.xy - 4.0 * data.xy;
			data.xy = texture(prev, old - DT * data.xy * texel).xy;

			float d = min(texture(dye, UV).x, 1.5);
			vec2 force = vec2(0.0, -buoyancy * d);
			// Slow churning in two sizes, so gas held in a pocket still rolls.
			vec2 wp = (UV / texel + origin) / sub;
			force += curl(wp * 0.22 + vec2(0.0, time * 0.21)) * churn * d;
			force += curl(wp * 0.63 + vec2(31.0 - time * 0.33, 7.0)) * churn * 0.55 * d;

			data.xy += DT * (VISC * lap - K / DT * dens_dif + force);
			data.xy = max(vec2(0.0), abs(data.xy) - 1e-4) * sign(data.xy);

			data.w = tr.y - tl.y - tu.x + td.x;
			vec2 vort = vec2(abs(tu.w) - abs(td.w), abs(tl.w) - abs(tr.w));
			vort *= vorticity / length(vort + 1e-9) * data.w;
			data.xy += vort;

			// Where the grid's gas is on the move, the field goes with it.
			vec2 fl = (texture(flux, UV).rg - 0.5) * 2.0;
			float fm = length(fl);
			if (fm > 0.04) {
				data.xy = mix(data.xy, fl * flux_gain, min(1.0, fm * 2.0) * 0.25);
			}

			// The keeper drags the gas along.
			vec2 kd = (UV / texel - keeper) / keeper_r;
			float kg = exp(-dot(kd, kd));
			if (dot(keeper_vel, keeper_vel) > 0.01) {
				data.xy = mix(data.xy, keeper_vel, kg * 0.8);
			}

			// Gas under pressure in the grid pushes outward; everything eases back to rest.
			data.z += jet * max(0.0, open_mix(tiles, UV, vec4(0.0, 4.0, 0.0, 0.0)) - 1.0);
			float hot = texture(tiles, UV).a;
			data.z += 0.12 * hot;
			data.y -= 0.6 * hot;
			data.z = mix(data.z, 1.0, 0.01);
			data.xy *= 0.995;
			data = clamp(data, vec4(-10.0, -10.0, 0.5, -10.0), vec4(10.0, 10.0, 3.0, 10.0));
		}
		COLOR = data;
	}
}
