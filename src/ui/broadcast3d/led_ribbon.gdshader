shader_type spatial;
render_mode unshaded;
// The LED ribbon that runs round the front of the lower bowl (3D overhaul M4): chevrons of the home, accent and away colours scrolling along it.
// Computed per pixel from the position along the ribbon, so it moves for free. Presentation only.

uniform vec3 colour_a : source_color = vec3(0.18, 0.44, 0.93);
uniform vec3 colour_b : source_color = vec3(0.98, 0.98, 0.98);
uniform vec3 colour_c : source_color = vec3(0.95, 0.54, 0.18);
uniform float speed = 2.2;
uniform float glow = 1.15;

varying vec3 local_position;

void vertex() {
	local_position = VERTEX;
}

void fragment() {
	float along = (local_position.x + local_position.z) * 0.35 - TIME * speed;
	float band = fract(along * 0.25 + local_position.y * 0.6);
	vec3 col = colour_a;
	col = mix(col, colour_b, step(0.33, band) * step(band, 0.4));
	col = mix(col, colour_c, step(0.7, band) * step(band, 0.85));
	ALBEDO = col * glow;
}
