class_name FcTeamEmblems
extends RefCounted
## The drawn parts of a team crest: eight crest SHAPES and 23 EMBLEMS, all simple vector figures made of polygons, lines, arcs and
## circles (no art files, so nothing to license and they stay sharp at every size). Everything is described in a unit square
## (-1 to 1, y down) and scaled by the caller. `color` is the emblem colour, `cut` the colour of the surface under it (some emblems
## cut small details out of themselves).


## The outline of a crest shape in unit space, centred on the origin (all are roughly convex so a scaled copy is a clean inset).
static func shape_points(id: String) -> PackedVector2Array:
	match id:
		"shield":
			return PackedVector2Array([Vector2(-0.85, -0.9), Vector2(0.85, -0.9), Vector2(0.85, 0.1), Vector2(0.7, 0.45), Vector2(0.4, 0.76), Vector2(0, 0.98),
				Vector2(-0.4, 0.76), Vector2(-0.7, 0.45), Vector2(-0.85, 0.1)])
		"roundel":
			return _ngon(40, 0.96, 0.0)
		"hexagon":
			return _ngon(6, 0.98, -PI / 2.0)
		"diamond":
			return PackedVector2Array([Vector2(0, -1), Vector2(0.86, 0), Vector2(0, 1), Vector2(-0.86, 0)])
		"pennant":
			return PackedVector2Array([Vector2(-0.9, -0.82), Vector2(0.9, -0.82), Vector2(0.9, 0.3), Vector2(0, 0.98), Vector2(-0.9, 0.3)])
		"banner":
			return PackedVector2Array([Vector2(-0.8, -0.92), Vector2(0.8, -0.92), Vector2(0.8, 0.96), Vector2(0, 0.62), Vector2(-0.8, 0.96)])
		"octagon":
			return _ngon(8, 0.98, PI / 8.0)
		_:   # "badge": a rounded square
			var pts := PackedVector2Array()
			for corner in [[Vector2(0.62, -0.62), -PI / 2.0], [Vector2(0.62, 0.62), 0.0], [Vector2(-0.62, 0.62), PI / 2.0], [Vector2(-0.62, -0.62), PI]]:
				for i in 7:
					var a: float = corner[1] + (PI / 2.0) * float(i) / 6.0
					pts.append((corner[0] as Vector2) + Vector2(cos(a), sin(a)) * 0.34)
			return pts


static func _ngon(sides: int, radius: float, start: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in sides:
		var a := start + TAU * float(i) / float(sides)
		pts.append(Vector2(cos(a), sin(a)) * radius)
	return pts


## Draws emblem `id` centred on `c` with radius `r` (pixels).
static func draw(canvas: CanvasItem, id: String, c: Vector2, r: float, color: Color, cut: Color) -> void:
	var w := maxf(1.0, r * 0.2)   # the usual stroke width
	match id:
		"star":
			canvas.draw_colored_polygon(_xf(_star(5, 1.0, 0.42), c, r), color)
		"spark":
			canvas.draw_colored_polygon(_xf(_star(4, 1.0, 0.26), c, r), color)
		"bolt":
			canvas.draw_colored_polygon(_xf(PackedVector2Array([Vector2(0.2, -1), Vector2(-0.6, 0.15), Vector2(-0.05, 0.15), Vector2(-0.25, 1), Vector2(0.6, -0.2), Vector2(0.05, -0.2)]), c, r), color)
		"crown":
			canvas.draw_colored_polygon(_xf(PackedVector2Array([Vector2(-1, 0.65), Vector2(-1, -0.55), Vector2(-0.5, 0.05), Vector2(0, -0.85), Vector2(0.5, 0.05), Vector2(1, -0.55), Vector2(1, 0.65)]), c, r), color)
			canvas.draw_rect(Rect2(c + Vector2(-1, 0.75) * r, Vector2(2, 0.25) * r), color)
		"peak":
			canvas.draw_colored_polygon(_xf(PackedVector2Array([Vector2(-1, 0.8), Vector2(-0.2, -0.9), Vector2(0.6, 0.8)]), c, r), color)
			canvas.draw_colored_polygon(_xf(PackedVector2Array([Vector2(0.05, 0.8), Vector2(0.55, -0.1), Vector2(1, 0.8)]), c, r), color)
		"wave":
			for k in 3:
				var pts := PackedVector2Array()
				for i in 17:
					var x := -1.0 + 2.0 * float(i) / 16.0
					pts.append(c + Vector2(x, -0.55 + 0.55 * k + 0.2 * sin(x * PI * 1.5 + float(k))) * r)
				canvas.draw_polyline(pts, color, w * 1.1, true)
		"flame":
			canvas.draw_colored_polygon(_xf(PackedVector2Array([Vector2(0.05, -1), Vector2(0.4, -0.45), Vector2(0.75, 0.1), Vector2(0.65, 0.65), Vector2(0.3, 0.97), Vector2(-0.3, 0.97),
				Vector2(-0.65, 0.65), Vector2(-0.7, 0.1), Vector2(-0.35, -0.25), Vector2(-0.25, -0.65)]), c, r), color)
			canvas.draw_colored_polygon(_xf(PackedVector2Array([Vector2(0, 0.2), Vector2(0.25, 0.55), Vector2(0.1, 0.85), Vector2(-0.1, 0.85), Vector2(-0.25, 0.55)]), c, r), cut)
		"wing":
			for i in 4:
				canvas.draw_line(c + Vector2(-0.9, 0.8) * r, c + Vector2(0.9, -0.85 + 0.38 * i) * r, color, w * 1.2, true)
		"chevrons":
			for k in [-0.3, 0.2, 0.7]:
				canvas.draw_polyline(_xf(PackedVector2Array([Vector2(-0.85, 0.15 + k), Vector2(0, -0.55 + k), Vector2(0.85, 0.15 + k)]), c, r), color, w * 1.1, true)
		"sun":
			canvas.draw_circle(c, r * 0.46, color)
			for i in 8:
				var a := TAU * float(i) / 8.0
				canvas.draw_line(c + Vector2(cos(a), sin(a)) * r * 0.68, c + Vector2(cos(a), sin(a)) * r * 1.0, color, w * 0.8, true)
		"crescent":
			var outer := _ngon(36, 0.92, 0.0)
			var inner := _ngon(36, 0.76, 0.0)
			for i in inner.size():
				inner[i] += Vector2(0.4, -0.12)
			for poly in Geometry2D.clip_polygons(outer, inner):
				canvas.draw_colored_polygon(_xf(poly, c, r), color)
		"gem":
			canvas.draw_colored_polygon(_xf(PackedVector2Array([Vector2(-0.95, -0.2), Vector2(-0.5, -0.85), Vector2(0.5, -0.85), Vector2(0.95, -0.2), Vector2(0, 0.97)]), c, r), color)
			for line in [[Vector2(-0.95, -0.2), Vector2(0.95, -0.2)], [Vector2(-0.5, -0.85), Vector2(-0.25, -0.2)], [Vector2(0.5, -0.85), Vector2(0.25, -0.2)], [Vector2(-0.25, -0.2), Vector2(0, 0.97)], [Vector2(0.25, -0.2), Vector2(0, 0.97)]]:
				canvas.draw_line(c + (line[0] as Vector2) * r, c + (line[1] as Vector2) * r, cut, maxf(1.0, r * 0.07))
		"target":
			canvas.draw_arc(c, r * 0.86, 0, TAU, 40, color, w * 0.9, true)
			canvas.draw_arc(c, r * 0.46, 0, TAU, 32, color, w * 0.9, true)
			canvas.draw_circle(c, r * 0.14, color)
		"pine":
			for tri in [[Vector2(0, -1), Vector2(0.55, -0.3), Vector2(-0.55, -0.3)], [Vector2(0, -0.55), Vector2(0.75, 0.3), Vector2(-0.75, 0.3)], [Vector2(0, -0.1), Vector2(0.95, 0.72), Vector2(-0.95, 0.72)]]:
				canvas.draw_colored_polygon(_xf(PackedVector2Array(tri), c, r), color)
			canvas.draw_rect(Rect2(c + Vector2(-0.12, 0.7) * r, Vector2(0.24, 0.3) * r), color)
		"arrow":
			canvas.draw_colored_polygon(_xf(PackedVector2Array([Vector2(0, -1), Vector2(0.78, -0.08), Vector2(0.3, -0.08), Vector2(0.3, 1), Vector2(-0.3, 1), Vector2(-0.3, -0.08), Vector2(-0.78, -0.08)]), c, r), color)
		"swoop":
			canvas.draw_colored_polygon(_xf(PackedVector2Array([Vector2(-1, -0.05), Vector2(-0.3, -0.6), Vector2(0.55, -0.8), Vector2(1, -0.55), Vector2(0.35, -0.2), Vector2(0.8, 0.55), Vector2(-0.05, 0.2), Vector2(-0.6, 0.55)]), c, r), color)
		"hoop":
			canvas.draw_line(c + Vector2(-0.85, -0.2) * r, c + Vector2(0.85, -0.2) * r, color, w * 1.1, true)
			for x in [-0.7, -0.35, 0.0, 0.35, 0.7]:
				canvas.draw_line(c + Vector2(x, -0.2) * r, c + Vector2(x * 0.5, 0.95) * r, color, maxf(1.0, r * 0.09), true)
			canvas.draw_line(c + Vector2(-0.6, 0.3) * r, c + Vector2(0.6, 0.3) * r, color, maxf(1.0, r * 0.09), true)
			canvas.draw_line(c + Vector2(-0.8, -0.95) * r, c + Vector2(-0.8, -0.2) * r, color, w * 0.9, true)
		"ball":
			canvas.draw_arc(c, r * 0.9, 0, TAU, 40, color, w * 0.9, true)
			canvas.draw_line(c + Vector2(0, -0.9) * r, c + Vector2(0, 0.9) * r, color, w * 0.6, true)
			canvas.draw_line(c + Vector2(-0.9, 0) * r, c + Vector2(0.9, 0) * r, color, w * 0.6, true)
			canvas.draw_arc(c + Vector2(-1.35, 0) * r, r * 0.95, -0.7, 0.7, 14, color, w * 0.6, true)
			canvas.draw_arc(c + Vector2(1.35, 0) * r, r * 0.95, PI - 0.7, PI + 0.7, 14, color, w * 0.6, true)
		"paw":
			canvas.draw_circle(c + Vector2(0, 0.42) * r, r * 0.5, color)
			for toe in [Vector2(-0.72, -0.02), Vector2(-0.27, -0.58), Vector2(0.27, -0.58), Vector2(0.72, -0.02)]:
				canvas.draw_circle(c + toe * r, r * 0.23, color)
		"claw":
			for i in 3:
				var x0 := -0.62 + 0.62 * i
				canvas.draw_polyline(_xf(PackedVector2Array([Vector2(x0 + 0.35, -0.95), Vector2(x0 + 0.08, -0.3), Vector2(x0 - 0.02, 0.3), Vector2(x0 - 0.33, 0.95)]), c, r), color, w * 1.1, true)
		"tower":
			canvas.draw_rect(Rect2(c + Vector2(-0.7, -0.1) * r, Vector2(1.4, 1.1) * r), color)
			for x in [-0.7, -0.15, 0.4]:
				canvas.draw_rect(Rect2(c + Vector2(x, -0.55) * r, Vector2(0.3, 0.45) * r), color)
			canvas.draw_colored_polygon(_xf(PackedVector2Array([Vector2(-0.2, 1), Vector2(-0.2, 0.55), Vector2(0, 0.38), Vector2(0.2, 0.55), Vector2(0.2, 1)]), c, r), cut)
		"bridge":
			canvas.draw_line(c + Vector2(-1, 0.45) * r, c + Vector2(1, 0.45) * r, color, w, true)
			for x in [-0.5, 0.5]:
				canvas.draw_line(c + Vector2(x, -0.7) * r, c + Vector2(x, 0.45) * r, color, w * 0.8, true)
			var cable := PackedVector2Array([c + Vector2(-1, 0.3) * r])
			for i in 11:
				var x := -0.5 + float(i) / 10.0
				cable.append(c + Vector2(x, -0.1 - 0.6 * pow(x / 0.5, 2.0)) * r)
			cable.append(c + Vector2(1, 0.3) * r)
			canvas.draw_polyline(cable, color, maxf(1.0, r * 0.1), true)
		"anchor":
			canvas.draw_arc(c + Vector2(0, -0.72) * r, r * 0.22, 0, TAU, 20, color, w * 0.8, true)
			canvas.draw_line(c + Vector2(0, -0.5) * r, c + Vector2(0, 0.9) * r, color, w * 0.9, true)
			canvas.draw_line(c + Vector2(-0.42, -0.25) * r, c + Vector2(0.42, -0.25) * r, color, w * 0.8, true)
			canvas.draw_arc(c + Vector2(0, 0.2) * r, r * 0.75, PI * 0.12, PI * 0.88, 24, color, w * 0.9, true)
		_:
			canvas.draw_circle(c, r * 0.8, color)


static func _star(points: int, outer: float, inner: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in points * 2:
		var radius := outer if i % 2 == 0 else inner
		var a := -PI / 2.0 + PI * float(i) / float(points)
		pts.append(Vector2(cos(a), sin(a)) * radius)
	return pts


## `pts` (unit space) moved to centre `c` and scaled by `r`.
static func _xf(pts: PackedVector2Array, c: Vector2, r: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	out.resize(pts.size())
	for i in pts.size():
		out[i] = c + pts[i] * r
	return out
