shader_type spatial;
render_mode depth_prepass_alpha, cull_disabled;
// V2 hair and facial hair (D-075). The mesh carries a hair DENSITY in its vertex colour (red: 0 bare, 1 full); the shader turns it into hair that thins
// into the skin: fine strands running along the head (UV v), coverage from the density, a soft sheen along the strands. Fades, tapers, hairlines and
// stubble come from the same shader with different densities. Shared by every player with the same hair colour.

uniform vec4 hair_color : source_color = vec4(0.06, 0.045, 0.035, 1.0);
uniform float strand_scale = 1400.0;
uniform float clump_scale = 80.0;
uniform float coverage_bias = 0.08;
uniform float sheen = 0.35;
uniform float coverage_scale = 1.15;   // facial hair uses less (it should read as hair on skin, not a solid patch)

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

void fragment() {
	float density = COLOR.r;
	// strands: thin streaks along v, broken into clumps
	float strands = noise(vec2(UV.x * strand_scale, UV.y * strand_scale * 0.08));
	float clumps = noise(UV * clump_scale);
	float coverage = clamp(density * coverage_scale + coverage_bias - (1.0 - strands) * (1.0 - density) * 0.9, 0.0, 1.0);
	vec3 base = hair_color.rgb * (0.6 + 0.7 * strands) * (0.8 + 0.4 * clumps);
	ALBEDO = base;
	ALPHA = coverage;
	ROUGHNESS = 0.82 - 0.15 * strands;   // hair is matte; a sheen along the strands, never a helmet shine
	SPECULAR = 0.18;
	RIM = sheen * density;
	RIM_TINT = 0.5;
}
