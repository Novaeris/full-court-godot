shader_type spatial;
// V2 basketball shoe upper (D-076): the master paints accent ZONES into the vertex colour (red: heel counter, side band, toe cap, collar); the shoe takes
// the base colour and the accent colour per player, so every shoe can be two-tone without separate meshes. A fine knit texture breaks up the upper.

uniform vec4 base_color : source_color = vec4(0.95, 0.95, 0.95, 1.0);
uniform vec4 accent_color : source_color = vec4(0.1, 0.25, 0.6, 1.0);
uniform float knit_scale = 900.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	float a = smoothstep(0.35, 0.65, COLOR.r);
	float knit = hash(floor(UV * knit_scale));
	vec3 c = mix(base_color.rgb, accent_color.rgb, a) * (0.94 + 0.08 * knit);
	ALBEDO = c;
	ROUGHNESS = mix(0.62, 0.45, a);   // accents are a smoother synthetic leather, the base a knit
	SPECULAR = 0.35;
}
