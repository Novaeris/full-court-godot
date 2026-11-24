shader_type spatial;
// The hardwood floor and ALL its markings (3D overhaul M3), computed per pixel in court feet, so the planks, the grain and the lines are razor sharp
// at any zoom (the old floor was a 10 pixels-per-foot picture with square dots for the arc). Dimensions are the real ones: 94 by 50 ft, a 16 ft lane
// 19 ft long, a 6 ft free-throw circle, a 23.75 ft three-point arc (22 ft in the corners), a 4 ft restricted arc, a 6 ft centre circle, 2 inch lines,
// the basket 5.25 ft from the baseline. The home team's colours paint the lane, the centre circle and the border. Presentation only.

uniform vec3 wood_light : source_color = vec3(0.79, 0.55, 0.31);
uniform vec3 wood_dark : source_color = vec3(0.66, 0.44, 0.23);
uniform vec3 seam_colour : source_color = vec3(0.42, 0.26, 0.13);
uniform vec3 line_colour : source_color = vec3(0.96, 0.95, 0.92);
uniform vec3 paint_colour : source_color = vec3(0.18, 0.44, 0.93);
uniform vec3 border_colour : source_color = vec3(0.12, 0.28, 0.6);
uniform vec3 circle_colour : source_color = vec3(0.18, 0.44, 0.93);
uniform float gloss = 0.3;
uniform float court_length = 94.0;
uniform float court_width = 50.0;
uniform float basket_x = 5.25;

varying vec2 court_xz;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash12(i), hash12(i + vec2(1, 0)), f.x), mix(hash12(i + vec2(0, 1)), hash12(i + vec2(1, 1)), f.x), f.y);
}

// 1 on a line of half-width hw at signed distance d, antialiased by the pixel size
float stroke(float d, float hw) {
	float aa = max(fwidth(d), 0.001);
	return 1.0 - smoothstep(hw - aa, hw + aa, abs(d));
}

void vertex() {
	court_xz = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
}

void fragment() {
	vec2 p = court_xz;
	float hw = 0.083;   // half of a 2 inch line
	vec2 c = vec2(court_length * 0.5, court_width * 0.5);
	bool inside = p.x >= 0.0 && p.x <= court_length && p.y >= 0.0 && p.y <= court_width;

	// --- planks: boards 3 inches wide running the length of the court, 8 ft long, staggered
	float plank = floor(p.y / 0.25);
	float stagger = hash12(vec2(plank, 1.0)) * 8.0;
	float board = floor((p.x + stagger) / 8.0);
	float id = hash12(vec2(board, plank));
	float grain = vnoise(vec2(p.x * 0.7 + id * 40.0, p.y * 26.0));
	float fine = vnoise(vec2(p.x * 4.0, p.y * 90.0 + id * 9.0));
	vec3 wood = mix(wood_dark, wood_light, clamp(0.25 + id * 0.55 + (grain - 0.5) * 0.35 + (fine - 0.5) * 0.12, 0.0, 1.0));
	float seam_side = smoothstep(0.012, 0.0, abs(fract(p.y / 0.25) - 0.5) * 0.25 - 0.1);
	float seam_end = smoothstep(0.03, 0.0, abs(fract((p.x + stagger) / 8.0) - 0.5) * 8.0 - 3.97);
	wood = mix(wood, seam_colour, max(seam_side * 0.55, seam_end * 0.7));

	vec3 col = wood;
	if (!inside) {
		col = mix(wood * 0.9, border_colour, 0.55);   // the border outside the lines, in the team's colour
	}
	// --- painted areas: the two lanes and the centre circle, the wood grain still showing through
	vec2 q = vec2(min(p.x, court_length - p.x), p.y);   // distance from the nearest baseline, so one set of lines does both ends
	float dz = abs(p.y - c.y);
	float lane = (inside && q.x < 19.0 && dz < 8.0) ? 1.0 : 0.0;
	col = mix(col, paint_colour * (0.55 + 0.6 * wood.r), lane * 0.88);
	float centre_dist = length(p - c);
	col = mix(col, circle_colour * (0.55 + 0.6 * wood.r), (inside && centre_dist < 2.0) ? 0.88 : 0.0);
	// the restricted area inside the lane keeps a lighter tone
	// --- lines
	float mark = 0.0;
	if (p.x > -0.3 && p.x < court_length + 0.3 && p.y > -0.3 && p.y < court_width + 0.3) {
		// boundary
		vec2 b = abs(p - c) - c;
		mark = max(mark, stroke(max(b.x, b.y), hw));
		// half-court line and the centre circle
		mark = max(mark, stroke(p.x - c.x, hw) * step(abs(p.y - c.y), c.y));
		mark = max(mark, stroke(centre_dist - 6.0, hw));
		mark = max(mark, stroke(centre_dist - 2.0, hw));
		// the lane: two side lines, the free-throw line
		mark = max(mark, stroke(dz - 8.0, hw) * step(q.x, 19.0));
		mark = max(mark, stroke(q.x - 19.0, hw) * step(dz, 8.0));
		// hash marks on the lane (block marks and tick marks)
		for (int k = 0; k < 4; k++) {
			float x = 7.0 + 3.0 * float(k);
			mark = max(mark, stroke(q.x - x, 0.06) * step(8.0, dz) * step(dz, 8.55));
		}
		// the free-throw circle: solid outside the lane, dashed inside
		float ft = length(vec2(q.x - 19.0, dz)) - 6.0;
		float dash = step(0.5, fract(atan(dz, q.x - 19.0) * 3.2));
		mark = max(mark, stroke(ft, hw) * (q.x > 19.0 ? 1.0 : dash));
		// the three-point line: an arc and two straight corner lines
		float arc = length(vec2(q.x - basket_x, dz)) - 23.75;
		mark = max(mark, stroke(arc, hw) * step(14.2, q.x));
		mark = max(mark, stroke(dz - 22.0, hw) * step(q.x, 14.2));
		// the restricted area: a 4 ft arc and the short lines to the backboard
		float ra = length(vec2(q.x - basket_x, dz)) - 4.0;
		mark = max(mark, stroke(ra, hw) * step(basket_x, q.x));
		mark = max(mark, stroke(dz - 4.0, hw) * step(4.0, q.x) * step(q.x, basket_x));
		// the backboard shadow line
		mark = max(mark, stroke(q.x - 4.0, hw) * step(dz, 3.0));
	}
	col = mix(col, line_colour, mark);

	float scuff = vnoise(p * vec2(0.9, 2.4));
	ALBEDO = col;
	ROUGHNESS = clamp(gloss + 0.18 * scuff + 0.12 * (1.0 - mark) * 0.0 + mark * 0.25, 0.05, 1.0);
	SPECULAR = 0.65;
	METALLIC = 0.0;
}
