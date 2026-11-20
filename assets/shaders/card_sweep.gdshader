shader_type canvas_item;
render_mode blend_add;

// A diagonal band of light that crosses a card once (progress goes from -0.3 to 1.3). Used on rare, epic and legendary cards
// when the pointer or focus arrives. It only adds light, so it never darkens the card, and it costs nothing while progress is outside 0..1.
uniform float progress : hint_range(-0.3, 1.3) = -0.3;
uniform vec4 tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float band_width = 0.16;

void fragment() {
	float d = (UV.x * 0.55 + UV.y * 0.45);
	float band = smoothstep(band_width, 0.0, abs(d - progress));
	COLOR = vec4(tint.rgb * band * 0.5, band * 0.5);
}
