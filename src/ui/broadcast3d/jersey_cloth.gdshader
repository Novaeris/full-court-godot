shader_type spatial;
// Team cloth for jerseys and shorts (Production Phase M1). One shader, parameters per player: the cloth colour, a fine knit weave, and an optional
// graphics texture laid out on the jersey UV (u around the body with the front at 0.5, v up from the hem) holding the number, surname and wordmark.
// Nothing here changes a game; it only draws.

uniform vec4 base_color : source_color = vec4(0.2, 0.4, 0.9, 1.0);
uniform sampler2D graphics : source_color, filter_linear_mipmap, repeat_enable, hint_default_transparent;
uniform float graphics_strength = 1.0;
uniform float weave_scale = 420.0;
uniform float weave_amount = 0.045;
uniform float cloth_roughness = 0.84;

void fragment() {
	vec4 g = texture(graphics, UV);
	vec2 f = UV * weave_scale;
	float weave = sin(f.x) * sin(f.y);
	vec3 cloth = base_color.rgb * (1.0 + weave_amount * weave);
	ALBEDO = mix(cloth, g.rgb, g.a * graphics_strength);
	ROUGHNESS = cloth_roughness;
}
