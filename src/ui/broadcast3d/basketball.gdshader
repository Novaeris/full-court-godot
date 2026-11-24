shader_type spatial;
// The basketball (3D overhaul M3): a leather-orange ball with a fine PEBBLED surface and the black CHANNELS of a real size 7 ball, all computed
// from the position on the sphere, so there is no texture to load or bake and the pattern turns with the ball. The pebbles perturb the lighting
// normal (cell noise), the channels are slightly sunken and darker. Presentation only.

uniform vec3 leather : source_color = vec3(0.86, 0.38, 0.12);
uniform vec3 channel_colour : source_color = vec3(0.05, 0.04, 0.035);
uniform float pebble_scale = 46.0;
uniform float pebble_strength = 0.22;
uniform float channel_width = 0.022;

varying vec3 local_pos;

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.yzx + 33.33);
	return fract((p.x + p.y) * p.z);
}

// 1 on a channel (with a soft edge), 0 elsewhere. A real ball has an equator, a meridian and two curved side channels.
float channels(vec3 n) {
	float w = channel_width;
	float equator = abs(n.y);
	float meridian = abs(n.x);
	float side = abs(abs(n.z) - 0.62 * (1.0 - n.y * n.y));
	float d = min(min(equator, meridian), side * 0.9);
	return 1.0 - smoothstep(w * 0.6, w * 1.2, d);
}

void vertex() {
	local_pos = normalize(VERTEX);
}

void fragment() {
	vec3 n = normalize(local_pos);
	float line = channels(n);
	// pebbles: a small random bump per cell of the sphere surface
	vec3 cell = floor(n * pebble_scale);
	vec3 jitter = vec3(hash13(cell), hash13(cell + 7.1), hash13(cell + 13.7)) - 0.5;
	vec3 bumped = normalize(NORMAL + (VIEW_MATRIX * vec4(jitter, 0.0)).xyz * pebble_strength * (1.0 - line));
	NORMAL = bumped;
	float tone = 0.93 + 0.14 * hash13(cell + 3.3);
	ALBEDO = mix(leather * tone, channel_colour, line);
	ROUGHNESS = mix(0.62, 0.9, line);
	SPECULAR = 0.35;
}
