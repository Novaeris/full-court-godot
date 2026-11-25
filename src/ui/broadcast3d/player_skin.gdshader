shader_type spatial;
// V2 player skin (D-075). One tone-neutral detail texture (pores, lips, creases from the CC0 MakeHuman skin) multiplied by the identity skin tone, a pore
// normal map, slightly varied roughness and a soft rim that stands in for light scattering under the skin (the compatibility renderer has no subsurface
// scattering). Shared by every player with the same tone.

uniform vec4 tone : source_color = vec4(0.62, 0.42, 0.29, 1.0);
uniform sampler2D detail : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D pores : hint_normal, filter_linear_mipmap, repeat_disable;
uniform float pore_depth = 0.55;
uniform float roughness_base = 0.58;
uniform float scatter = 0.12;

void fragment() {
	vec3 d = texture(detail, UV).rgb * 2.0;
	vec3 skin = tone.rgb * d;
	ALBEDO = clamp(skin, vec3(0.0), vec3(1.0));
	NORMAL_MAP = texture(pores, UV).rgb;
	NORMAL_MAP_DEPTH = pore_depth;
	ROUGHNESS = clamp(roughness_base + (1.0 - d.r * 0.5) * 0.1, 0.3, 0.85);
	SPECULAR = 0.24;
	RIM = scatter;
	RIM_TINT = 0.7;
}
