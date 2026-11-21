class_name FcRevealFx
extends Control
## The effects layer of the pack-opening reveal: particles, light rays, a shockwave ring, a screen flash, a dimmed room and a banner, drawn
## by ONE node (so a legendary pull costs a few draw calls, not a hundred particle nodes). Every effect is an EXPLICIT method (burst, rays,
## shockwave, flash, dim, banner), never a simulated mouse event, and every effect is bounded and cleaned up:
##   - at most `particles` particles alive at once (FcRevealSpec.caps; extra ones are dropped, not queued),
##   - at most `flashes_per_second` flashes (a flash asked for too soon is refused; photosensitivity safety),
##   - at most `rays_at_once` ray fans and `banners_at_once` banners,
##   - processing stops by itself when nothing is alive, and stop_all() clears everything at once (used by Skip and when the reveal ends).
## The look is cosmetic and uses its OWN seeded generator (seeded from the opening id), so a replay looks the same and nothing here ever
## touches game state or any game RNG. With reduced motion every method does nothing.

var _rng := RandomNumberGenerator.new()
var _pos := PackedVector2Array()
var _vel := PackedVector2Array()
var _life := PackedFloat32Array()
var _max_life := PackedFloat32Array()
var _size := PackedFloat32Array()
var _colors := PackedColorArray()
var _rays: Array = []        # [{center, color, count, age, seconds}]
var _rings: Array = []       # [{center, color, age, seconds}]
var _flash_color := Color(1, 1, 1, 0)
var _dim_amount := 0.0
var _dim_tween: Tween = null
var _flash_tween: Tween = null
var _banners: Array = []
var _last_flash := -10.0
## Counters for tests and the performance review.
var stats := {"particles_requested": 0, "particles_dropped": 0, "flashes": 0, "flashes_refused": 0, "peak_particles": 0}


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	set_process(false)


## Seeds the cosmetic generator (the reveal passes a hash of the opening id): the same opening looks the same.
func seed_from(text: String) -> void:
	_rng.seed = FcPlayerVisual.fnv1a(text)


func particle_count() -> int:
	return _pos.size()


## True while anything is still showing (particles, rays, rings, a dim, a flash, a banner).
func is_active() -> bool:
	return _pos.size() > 0 or not _rays.is_empty() or not _rings.is_empty() or _dim_amount > 0.001 or _flash_color.a > 0.002 or not _banners.is_empty()


## A burst of `count` sparks from `center` (capped). `speed` in pixels per second.
func burst(center: Vector2, color: Color, count: int, speed: float = 260.0) -> void:
	if FcMotion.reduced or count <= 0:
		return
	var cap := int(FcRevealSpec.caps()["particles"])
	stats["particles_requested"] += count
	for i in count:
		if _pos.size() >= cap:
			stats["particles_dropped"] += 1
			continue
		var angle := _rng.randf() * TAU
		var v := speed * (0.35 + _rng.randf() * 0.65)
		_pos.append(center)
		_vel.append(Vector2(cos(angle), sin(angle) - 0.3) * v)
		var life := 0.6 + _rng.randf() * 0.7
		_life.append(life)
		_max_life.append(life)
		_size.append(2.0 + _rng.randf() * 3.5)
		_colors.append(color.lightened(_rng.randf() * 0.5))
	stats["peak_particles"] = maxi(int(stats["peak_particles"]), _pos.size())
	set_process(true)


## A fan of light beams from `center` that turn slowly and fade (a few at once at most).
func rays(center: Vector2, color: Color, count: int, seconds: float = 1.2) -> void:
	if FcMotion.reduced or count <= 0:
		return
	if _rays.size() >= int(FcRevealSpec.caps()["rays_at_once"]):
		_rays.pop_front()
	_rays.append({"center": center, "color": color, "count": count, "age": 0.0, "seconds": seconds})
	set_process(true)


## A ring that expands from `center` and fades.
func shockwave(center: Vector2, color: Color, seconds: float = 0.55) -> void:
	if FcMotion.reduced:
		return
	_rings.append({"center": center, "color": color, "age": 0.0, "seconds": seconds})
	set_process(true)


## A full-layer flash that fades. Returns false when refused for coming too soon after the last one (at most N per second).
func flash(color: Color, strength: float, seconds: float = 0.4) -> bool:
	if FcMotion.reduced or strength <= 0.0:
		return false
	var gap := 1.0 / float(maxi(1, int(FcRevealSpec.caps()["flashes_per_second"])))
	var now := Time.get_ticks_msec() / 1000.0
	if now - _last_flash < gap:
		stats["flashes_refused"] += 1
		return false
	_last_flash = now
	stats["flashes"] += 1
	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()
	_flash_color = Color(color.lightened(0.5), clampf(strength, 0.0, 0.8))
	_flash_tween = create_tween()
	_flash_tween.tween_property(self, "_flash_color:a", 0.0, seconds)
	set_process(true)
	return true


## Darkens the room around the card to `amount` (0 to 1) over `seconds`. dim(0) lights it again.
func dim(amount: float, seconds: float = 0.3) -> void:
	if FcMotion.reduced:
		return
	if _dim_tween != null and _dim_tween.is_valid():
		_dim_tween.kill()
	_dim_tween = create_tween()
	_dim_tween.tween_property(self, "_dim_amount", clampf(amount, 0.0, 0.85), seconds)
	set_process(true)


## A big word that pops in and fades out, with an optional smaller supporting label under it (a legendary pull: the PLAYER's name is the
## banner and "LEGENDARY" the label). Both are drawn as Labels under this node.
func banner(text: String, color: Color, seconds: float = 1.1, sub_text: String = "") -> void:
	if FcMotion.reduced:
		return
	while _banners.size() >= int(FcRevealSpec.caps()["banners_at_once"]):
		var old: Control = _banners.pop_front()
		if is_instance_valid(old):
			old.queue_free()
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 0)
	box.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)   # as wide as the stage, so the centred text is centred on the card
	box.offset_top = 6.0
	var label := FcUiTables.label(text, FcUiTokens.TYPE_DISPLAY_XL, true)
	label.add_theme_color_override("font_color", Color(1, 1, 1))
	label.add_theme_color_override("font_outline_color", Color(color.darkened(0.3), 0.9))
	label.add_theme_constant_override("outline_size", 10)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(label)
	if sub_text != "":
		var sub := FcUiTables.label(sub_text, FcUiTokens.TYPE_H2, true)
		sub.add_theme_color_override("font_color", color.lightened(0.3))
		sub.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
		sub.add_theme_constant_override("outline_size", 6)
		sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(sub)
	add_child(box)
	_banners.append(box)
	FcMotion.pop_in(box, 0.25)
	var tw := box.create_tween()
	tw.tween_interval(maxf(0.1, seconds - 0.25))
	tw.tween_property(box, "modulate:a", 0.0, 0.25)
	tw.tween_callback(func() -> void:
		_banners.erase(box)
		box.queue_free())


## Clears everything at once: used by Skip, by the summary and when the reveal is freed. Safe to call at any time.
func stop_all() -> void:
	for tw in [_dim_tween, _flash_tween]:
		if tw != null and tw.is_valid():
			tw.kill()
	_dim_tween = null
	_flash_tween = null
	_pos.clear()
	_vel.clear()
	_life.clear()
	_max_life.clear()
	_size.clear()
	_colors.clear()
	_rays.clear()
	_rings.clear()
	_dim_amount = 0.0
	_flash_color = Color(1, 1, 1, 0)
	for b in _banners:
		if is_instance_valid(b):
			b.queue_free()
	_banners.clear()
	set_process(false)
	queue_redraw()


func _process(delta: float) -> void:
	var i := _pos.size() - 1
	while i >= 0:
		_life[i] -= delta
		if _life[i] <= 0.0:
			_remove_particle(i)
		else:
			_vel[i] += Vector2(0, 380) * delta
			_pos[i] += _vel[i] * delta
		i -= 1
	for list in [_rays, _rings]:
		for j in range(list.size() - 1, -1, -1):
			list[j]["age"] += delta
			if list[j]["age"] >= list[j]["seconds"]:
				list.remove_at(j)
	queue_redraw()
	if not is_active():
		set_process(false)


func _remove_particle(i: int) -> void:
	var last := _pos.size() - 1
	_pos[i] = _pos[last]
	_vel[i] = _vel[last]
	_life[i] = _life[last]
	_max_life[i] = _max_life[last]
	_size[i] = _size[last]
	_colors[i] = _colors[last]
	_pos.resize(last)
	_vel.resize(last)
	_life.resize(last)
	_max_life.resize(last)
	_size.resize(last)
	_colors.resize(last)


func _draw() -> void:
	if _dim_amount > 0.001:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.01, 0.01, 0.03, _dim_amount))
	for ray in _rays:
		var f: float = ray["age"] / ray["seconds"]
		var alpha := sin(f * PI) * 0.34
		var center: Vector2 = ray["center"]
		var color: Color = ray["color"]
		var reach := maxf(size.x, size.y)
		for k in int(ray["count"]):
			var a := TAU * float(k) / float(ray["count"]) + f * 0.9
			var w := 0.06
			draw_polygon(PackedVector2Array([center, center + Vector2(cos(a - w), sin(a - w)) * reach, center + Vector2(cos(a + w), sin(a + w)) * reach]), PackedColorArray([Color(color, alpha), Color(color, 0.0), Color(color, 0.0)]))
	for ring in _rings:
		var f2: float = ring["age"] / ring["seconds"]
		draw_arc(ring["center"], 20.0 + f2 * 260.0, 0.0, TAU, 48, Color(ring["color"], (1.0 - f2) * 0.7), 5.0 * (1.0 - f2) + 1.0, true)
	for i in _pos.size():
		var life_f := _life[i] / _max_life[i]
		var c := _colors[i]
		draw_circle(_pos[i], _size[i] * (0.5 + life_f * 0.5), Color(c.r, c.g, c.b, clampf(life_f * 1.6, 0.0, 1.0)))
	if _flash_color.a > 0.002:
		draw_rect(Rect2(Vector2.ZERO, size), _flash_color)
