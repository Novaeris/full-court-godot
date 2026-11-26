shader_type spatial;
render_mode cull_disabled;   // open cloth (hem, armholes, leg openings): the inside shows the cloth, not the body behind it
// Team cloth for jerseys and shorts (Production Phase M1). One shader, parameters per player: the cloth colour, a fine knit weave, and an optional
// graphics texture laid out on the jersey UV (u around the body with the front at 0.5, v up from the hem) holding the number, surname and wordmark.
// Nothing here changes a game; it only draws.

uniform vec4 base_color : source_color = vec4(0.2, 0.4, 0.9, 1.0);
uniform sampler2D graphics : source_color, filter_linear_mipmap, repeat_enable, hint_default_transparent;
uniform float graphics_strength = 1.0;
uniform float weave_scale = 420.0;
uniform float weave_amount = 0.045;
uniform float cloth_roughness = 0.84;
// side panels (u = 0.25 and 0.75 are the sides of the body): a band in panel_color edged with piping in piping_color
uniform vec4 panel_color : source_color = vec4(0.1, 0.25, 0.6, 1.0);
uniform vec4 piping_color : source_color = vec4(1.0, 0.8, 0.2, 1.0);
uniform float panel_width = 0.0;   // 0 = no panel (shorts use it, jerseys too)
uniform float piping_width = 0.006;

void fragment() {
	vec4 g = texture(graphics, UV);
	vec2 f = UV * weave_scale;
	float weave = sin(f.x) * sin(f.y);
	vec3 cloth = base_color.rgb * (1.0 + weave_amount * weave);
	// stitched seams down the sides (u = 0.25 and 0.75) and a stitch row beside them
	float side_seam = min(abs(UV.x - 0.25), abs(UV.x - 0.75));
	float seam = 1.0 - smoothstep(0.0012, 0.0028, side_seam);
	float stitch = (1.0 - smoothstep(0.0, 0.0012, abs(side_seam - 0.006))) * step(0.5, fract(UV.y * 140.0));
	cloth *= 1.0 - 0.18 * seam - 0.10 * stitch;
	if (panel_width > 0.0) {
		float from_side = min(abs(UV.x - 0.25), abs(UV.x - 0.75));
		float in_panel = 1.0 - smoothstep(panel_width - 0.002, panel_width, from_side);
		float on_piping = (1.0 - smoothstep(0.0, 0.0015, abs(from_side - panel_width - piping_width * 0.5) - piping_width * 0.5));
		cloth = mix(cloth, panel_color.rgb * (1.0 + weave_amount * weave), in_panel);
		cloth = mix(cloth, piping_color.rgb, on_piping);
	}
	ALBEDO = mix(cloth, g.rgb, g.a * graphics_strength);
	ROUGHNESS = cloth_roughness;
}
