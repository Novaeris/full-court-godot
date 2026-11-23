shader_type spatial;
render_mode unshaded, cull_disabled;
// The 3D crowd (Broadcast pass 2, M5): camera-facing cards with their own idle sway, a cheer (a jump), a groan (a slump) and a stadium wave, all
// computed here from three numbers the scene sets each frame, so reacting costs the CPU nothing per fan (one MultiMesh, a few draw calls).
// Per-instance colour and size come from the MultiMesh (FcCrowdPlan). Presentation only.

uniform float cheer : hint_range(0.0, 1.0) = 0.0;
uniform float groan : hint_range(0.0, 1.0) = 0.0;
uniform float wave_pos = -1.0;   // 0 to 1 around the arena, negative = no wave
uniform vec2 arena_centre = vec2(47.0, 25.0);

varying vec4 fan_colour;

void vertex() {
	fan_colour = COLOR;
	vec4 origin = MODEL_MATRIX[3];
	float id = float(INSTANCE_ID);
	float phase = fract(sin(id * 12.9898) * 43758.5453) * 6.2831;
	float idle = sin(TIME * 1.7 + phase) * 0.04;
	float jump = max(0.0, sin(TIME * 8.0 + phase)) * 0.45 * cheer;
	float slump = -0.22 * groan;
	float angle = atan(origin.z - arena_centre.y, origin.x - arena_centre.x) / 6.2831 + 0.5;
	float gap = abs(fract(angle - wave_pos + 0.5) - 0.5);
	float wave = wave_pos >= 0.0 ? smoothstep(0.07, 0.0, gap) * 0.8 : 0.0;
	float lift = idle + jump + slump + wave;
	float sx = length(MODEL_MATRIX[0].xyz);
	float sy = length(MODEL_MATRIX[1].xyz) * (1.0 + 0.25 * wave - 0.1 * groan);
	mat4 card = mat4(INV_VIEW_MATRIX[0] * sx, INV_VIEW_MATRIX[1] * sy, INV_VIEW_MATRIX[2], vec4(origin.xyz + vec3(0.0, lift, 0.0), 1.0));
	MODELVIEW_MATRIX = VIEW_MATRIX * card;
}

void fragment() {
	ALBEDO = fan_colour.rgb;
}
