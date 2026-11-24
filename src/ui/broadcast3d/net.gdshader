shader_type spatial;
render_mode unshaded, cull_disabled;
// The basket's net (3D overhaul M3): a diamond mesh of thin lines hanging from the rim. When a shot goes through, `swish` (1 down to 0, set by code)
// makes it swing and ripple, strongest at the bottom where the net is free. The mesh itself never changes, so the motion costs nothing per frame.

uniform float swish : hint_range(0.0, 1.0) = 0.0;
uniform float depth = 1.5;
uniform vec3 net_colour : source_color = vec3(0.95, 0.95, 0.95);

void vertex() {
	float free_end = clamp(-VERTEX.y / depth, 0.0, 1.0);
	float wave = sin(TIME * 22.0 - VERTEX.y * 7.0) * swish;
	VERTEX.x += wave * 0.07 * free_end;
	VERTEX.z += cos(TIME * 18.0 - VERTEX.y * 5.0) * 0.05 * swish * free_end;
	VERTEX.xz *= 1.0 + 0.12 * swish * free_end * (0.5 + 0.5 * sin(TIME * 25.0));   // the ball stretches it open as it passes
}

void fragment() {
	ALBEDO = net_colour;
	ALPHA = 0.92;
}
