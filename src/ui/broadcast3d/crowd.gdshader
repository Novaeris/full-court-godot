shader_type spatial;
render_mode unshaded, cull_disabled;
// The 3D crowd (Broadcast pass 2, M5; fans drawn in 3D overhaul M4): camera-facing cards with their own idle sway, a cheer (a jump with the ARMS UP), a
// groan (a slump) and a stadium wave, all computed here from three numbers the scene sets each frame, so reacting costs the CPU nothing per fan (one
// MultiMesh, a few draw calls). Each card is DRAWN as a fan: head, ears, hair or a cap, a neck and shoulders in the clothing colour (from the MultiMesh
// colour, FcCrowdPlan), with a skin tone, hair colour, hair style and clothing pattern picked per fan from its instance id, so a section is a crowd of
// different people and not a field of rectangles. Upper rows are a little darker, as in a real arena. Presentation only.

uniform float cheer : hint_range(0.0, 1.0) = 0.0;
uniform float groan : hint_range(0.0, 1.0) = 0.0;
uniform float wave_pos = -1.0;   // 0 to 1 around the arena, negative = no wave
uniform vec2 arena_centre = vec2(47.0, 25.0);
uniform vec3 skin_a : source_color = vec3(0.96, 0.82, 0.70);
uniform vec3 skin_b : source_color = vec3(0.86, 0.66, 0.48);
uniform vec3 skin_c : source_color = vec3(0.66, 0.44, 0.28);
uniform vec3 skin_d : source_color = vec3(0.45, 0.28, 0.17);
uniform vec3 skin_e : source_color = vec3(0.30, 0.18, 0.11);
uniform vec3 hair_dark : source_color = vec3(0.08, 0.06, 0.05);
uniform vec3 hair_brown : source_color = vec3(0.30, 0.18, 0.10);
uniform vec3 hair_light : source_color = vec3(0.78, 0.62, 0.34);
uniform vec3 hair_grey : source_color = vec3(0.62, 0.62, 0.62);

varying vec4 fan_colour;
varying vec3 fan_hash;
varying float fan_arms;
varying float fan_light;

float h11(float p) {
	return fract(sin(p * 12.9898) * 43758.5453);
}

void vertex() {
	fan_colour = COLOR;
	vec4 origin = MODEL_MATRIX[3];
	float id = float(INSTANCE_ID);
	fan_hash = vec3(h11(id + 1.3), h11(id * 1.7 + 9.1), h11(id * 2.3 + 4.7));
	float phase = fract(sin(id * 12.9898) * 43758.5453) * 6.2831;
	float idle = sin(TIME * 1.7 + phase) * 0.04;
	float jump = max(0.0, sin(TIME * 8.0 + phase)) * 0.45 * cheer;
	float slump = -0.22 * groan;
	float angle = atan(origin.z - arena_centre.y, origin.x - arena_centre.x) / 6.2831 + 0.5;
	float gap = abs(fract(angle - wave_pos + 0.5) - 0.5);
	float wave = wave_pos >= 0.0 ? smoothstep(0.07, 0.0, gap) * 0.8 : 0.0;
	float lift = idle + jump + slump + wave;
	// arms go up when the fan cheers or is in the wave (each fan a little differently)
	fan_arms = clamp(max(cheer * step(0.35, fan_hash.z + cheer * 0.45), wave * 1.2), 0.0, 1.0);
	fan_light = mix(1.0, 0.7, smoothstep(2.0, 22.0, origin.y));
	float sx = length(MODEL_MATRIX[0].xyz);
	float sy = length(MODEL_MATRIX[1].xyz) * (1.0 + 0.25 * wave - 0.1 * groan);
	mat4 card = mat4(INV_VIEW_MATRIX[0] * sx, INV_VIEW_MATRIX[1] * sy, INV_VIEW_MATRIX[2], vec4(origin.xyz + vec3(0.0, lift, 0.0), 1.0));
	MODELVIEW_MATRIX = VIEW_MATRIX * card;
}

float ellipse(vec2 p, vec2 centre, vec2 radii) {
	vec2 q = (p - centre) / radii;
	return 1.0 - smoothstep(0.85, 1.0, length(q));
}

void fragment() {
	// feet from the top centre of the 0.9 by 1.5 ft card
	vec2 q = vec2((UV.x - 0.5) * 0.9, UV.y * 1.5);
	float skin_pick = fan_hash.x;
	vec3 skin = skin_a;
	skin = mix(skin, skin_b, step(0.2, skin_pick));
	skin = mix(skin, skin_c, step(0.45, skin_pick));
	skin = mix(skin, skin_d, step(0.7, skin_pick));
	skin = mix(skin, skin_e, step(0.88, skin_pick));
	float hair_pick = fan_hash.y;
	vec3 hair = hair_dark;
	hair = mix(hair, hair_brown, step(0.4, hair_pick));
	hair = mix(hair, hair_light, step(0.72, hair_pick));
	hair = mix(hair, hair_grey, step(0.92, hair_pick));
	float style = floor(fan_hash.z * 5.0);   // 0 short hair, 1 bald, 2 long hair, 3 cap, 4 afro

	float head = ellipse(q, vec2(0.0, 0.40), vec2(0.17, 0.205));
	float neck = step(abs(q.x), 0.07) * step(0.50, q.y) * step(q.y, 0.66);
	// shoulders and chest: a rounded block in the clothing colour; a stripe or a darker hem for variety
	float torso = (1.0 - smoothstep(0.0, 0.05, abs(q.x) - 0.36)) * step(0.62, q.y);
	torso *= 1.0 - smoothstep(0.62, 0.70, 0.70 - (0.62 - q.y)) * 0.0;
	float round_top = ellipse(q, vec2(0.0, 0.86), vec2(0.40, 0.30));
	torso = max(torso * step(0.75, q.y), round_top * step(0.62, q.y));
	// arms up: two forearms rising beside the head
	float arm_len = 0.5 * fan_arms;
	float arm_l = step(abs(q.x - 0.36), 0.055) * step(0.62 - arm_len - 0.1, q.y) * step(q.y, 0.78);
	float arm_r = step(abs(q.x + 0.36), 0.055) * step(0.62 - arm_len - 0.1, q.y) * step(q.y, 0.78);
	float arms = max(arm_l, arm_r) * step(0.01, fan_arms);
	float fist = max(ellipse(q, vec2(0.36, 0.62 - arm_len - 0.1), vec2(0.07, 0.07)), ellipse(q, vec2(-0.36, 0.62 - arm_len - 0.1), vec2(0.07, 0.07))) * step(0.01, fan_arms);

	float hair_mask = 0.0;
	if (style < 0.5) {
		hair_mask = ellipse(q, vec2(0.0, 0.33), vec2(0.185, 0.2)) * step(q.y, 0.37);
	} else if (style > 1.5 && style < 2.5) {
		hair_mask = max(ellipse(q, vec2(0.0, 0.33), vec2(0.19, 0.2)) * step(q.y, 0.37), step(abs(q.x), 0.19) * step(0.3, q.y) * step(q.y, 0.62) * step(0.12, abs(q.x) + 0.0));
	} else if (style > 3.5) {
		hair_mask = ellipse(q, vec2(0.0, 0.31), vec2(0.27, 0.27)) * (1.0 - head * step(0.36, q.y));
	}
	bool cap = style > 2.5 && style < 3.5;
	float cap_mask = cap ? ellipse(q, vec2(0.0, 0.31), vec2(0.19, 0.12)) * step(q.y, 0.36) + step(abs(q.x - 0.03), 0.14) * step(abs(q.y - 0.355), 0.025) : 0.0;

	vec3 cloth = fan_colour.rgb;
	float stripe = step(0.5, fract(q.y * 5.0)) * step(0.5, fan_hash.x);
	cloth = mix(cloth, cloth * 0.75 + 0.1, stripe * 0.5);

	vec3 col = cloth;
	float mask = max(max(torso, head), max(arms, fist));
	col = mix(col, skin * 0.93, max(head, max(neck, max(arms, fist))));
	col = mix(col, hair, clamp(hair_mask, 0.0, 1.0));
	col = mix(col, fan_colour.rgb * 0.8, clamp(cap_mask, 0.0, 1.0));
	// two small dark eyes on the face so a crowd close to the camera is a crowd of faces
	float eyes = max(ellipse(q, vec2(-0.065, 0.41), vec2(0.02, 0.016)), ellipse(q, vec2(0.065, 0.41), vec2(0.02, 0.016)));
	col = mix(col, vec3(0.08), eyes * head * 0.8);
	mask = max(max(mask, neck), max(clamp(hair_mask, 0.0, 1.0), clamp(cap_mask, 0.0, 1.0)));
	ALBEDO = col * fan_light;
	ALPHA = mask;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
}
