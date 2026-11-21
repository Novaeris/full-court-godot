class_name FcPortraitBake
extends Node
## The portrait texture cache (D-059, approved with a hard 20 MB budget). A procedural figure is drawn ONCE into a small off-screen viewport, the
## picture is copied into an ImageTexture and the viewport is freed; every later draw of the same player at the same size is one textured
## rectangle. The high-fidelity figure costs 1 to 2 ms to draw (tools/portrait_bench.gd); a baked one costs a single draw command.
## Rules:
##   - Correctness never depends on it: with no cache (unit tests, headless, a failed bake) the figure is drawn live, identically.
##   - HARD BUDGET: the pictures held by the cache never exceed `budget_bytes` (20 MB by default). Before a picture is stored the least recently
##     used ones are evicted until it fits. (A texture a screen is still showing stays alive through that screen's own reference; the cache
##     simply forgets it, so the ceiling holds for what the cache retains.)
##   - Never the wrong picture: the key holds EVERYTHING that changes the picture (player key, art tier, age, team colours, number or letters,
##     the identity options, body inputs, crop, pixel size, aspect, which figure). A trade (new colours) or a birthday (new age) is a new key.
##   - Right resolution: the picture is baked at the on-screen pixel size (scaled by the canvas transform), rounded UP to the next size step so
##     near sizes share one picture; it is never drawn larger than baked.
##   - Bounded work: at most `bakes_per_frame` new pictures start per frame; the rest are drawn live that frame.
##   - Release: clear() frees everything (FcApp calls it when a game is left or loaded).
## One instance lives in the scene tree (FcApp adds it); `shared` is that instance (null when none: callers draw live).

signal baked(key: String)

const MB := 1024 * 1024
const SIZE_STEPS := [32, 48, 64, 96, 128, 192, 256, 384, 512]
## Extra margin baked around the figure (a fraction of its size on each side) so hair and shoulders that reach past the rectangle are kept, as they are when drawn live.
const MARGIN := 0.12

static var shared: FcPortraitBake = null

var budget_bytes: int = 20 * MB
var bakes_per_frame: int = 16
var enabled: bool = true
var _entries: Dictionary = {}   # key -> {texture: ImageTexture, bytes: int, size: Vector2i}
var _order: Array = []          # least recently used first
var _pending: Dictionary = {}   # key -> {viewport: SubViewport being rendered, frame: the frame it started in}
var _bytes: int = 0
var _started_this_frame: int = 0
var _frame_of_count: int = -1
## Counters for the performance report: hits (served from the cache), misses (pictures that had to be baked), live_draws (draws that fell back to the live figure while a
## picture was being baked), evicted, baked, bake_usec (time spent starting and finishing bakes), failed.
var stats := {"hits": 0, "misses": 0, "evicted": 0, "baked": 0, "bake_usec": 0, "failed": 0, "peak_bytes": 0, "live_draws": 0}


class _Canvas extends Control:
	var visual: Dictionary = {}
	var crop := "bust"
	var margin := Vector2.ZERO

	func _draw() -> void:
		var inner := Rect2(margin, size - margin * 2.0)
		match crop:
			"head":
				FcPlayerFigure.draw_headshot_live(self, inner, visual)
			"full":
				FcPlayerFigure.draw_live(self, inner, visual, true)
			_:
				FcPlayerFigure.draw_live(self, inner, visual, false)


func _enter_tree() -> void:
	if shared == null:
		shared = self


func _exit_tree() -> void:
	if shared == self:
		shared = null
	if RenderingServer.frame_post_draw.is_connected(_on_frame_post_draw):
		RenderingServer.frame_post_draw.disconnect(_on_frame_post_draw)
	_pending.clear()


## Everything that changes the picture, as one text key.
static func cache_key(visual: Dictionary, pixels: Vector2i, crop: String, aspect: float = 1.0) -> String:
	var uniform: Dictionary = visual.get("uniform", {})
	var id: Dictionary = visual.get("identity", {})
	var body: Dictionary = visual.get("body_in", {})
	return "%s|t%d|age%d|%s|%s|n%d|%s|%s|%dx%d|a%.2f|%s|%s%s%s%s%s|b%s" % [visual.get("key", ""), int(visual.get("tier", 2)), int(visual.get("age", 0)), (uniform.get("primary", Color.BLACK) as Color).to_html(false),
		(uniform.get("secondary", Color.BLACK) as Color).to_html(false), int(uniform.get("number", 0)), str(uniform.get("abbreviation", "")), crop, pixels.x, pixels.y, aspect,
		"hd" if FcPlayerFigure.hd_enabled else "v1", id.get("skin", ""), id.get("hair", ""), id.get("face", ""), id.get("facial_hair", ""), id.get("build", ""),
		"%s/%s/%s" % [body.get("height_cm", 0), body.get("weight_kg", 0), body.get("position", "")]]


## The size step (on the longer side) that covers `needed` pixels.
static func step_for(needed: float) -> int:
	for step in SIZE_STEPS:
		if float(step) >= needed:
			return step
	return SIZE_STEPS[SIZE_STEPS.size() - 1]


## The baked picture for a figure drawn into a rectangle of `logical_size` on a canvas whose pixel scale is `pixel_scale`, or null when it is not
## (yet) available: the caller then draws the figure live. The picture covers the rectangle plus MARGIN on every side (draw it into
## `rect.grow_individual(...)`: see FcPlayerFigure.draw).
func texture_for(visual: Dictionary, logical_size: Vector2, pixel_scale: float, crop: String) -> Texture2D:
	if not enabled or not is_inside_tree() or logical_size.x < 1.0 or logical_size.y < 1.0:
		return null
	var padded := logical_size * (1.0 + 2.0 * MARGIN) * maxf(pixel_scale, 0.5)
	var step := step_for(maxf(padded.x, padded.y))
	var ratio := float(step) / maxf(padded.x, padded.y)
	var pixels := Vector2i(maxi(8, roundi(padded.x * ratio)), maxi(8, roundi(padded.y * ratio)))
	var key := cache_key(visual, pixels, crop, snappedf(logical_size.x / logical_size.y, 0.01))
	if _entries.has(key):
		stats["hits"] += 1
		_order.erase(key)
		_order.append(key)
		return _entries[key]["texture"]
	stats["live_draws"] += 1
	if not _pending.has(key) and _start_bake(key, visual, pixels, crop, logical_size):
		stats["misses"] += 1   # a picture that is needed and not there: it is being baked now and drawn live until then
	return null


func _start_bake(key: String, visual: Dictionary, pixels: Vector2i, crop: String, logical_size: Vector2) -> bool:
	if _pending.has(key):
		return false
	var frame := Engine.get_process_frames()
	if frame != _frame_of_count:
		_frame_of_count = frame
		_started_this_frame = 0
	if _started_this_frame >= bakes_per_frame:
		return false
	_started_this_frame += 1
	var t0 := Time.get_ticks_usec()
	var viewport := SubViewport.new()
	viewport.size = pixels
	viewport.transparent_bg = true
	viewport.disable_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	var canvas := _Canvas.new()
	canvas.visual = visual.duplicate(true)
	canvas.crop = crop
	canvas.size = Vector2(pixels)
	# the rectangle inside the picture: the logical rectangle scaled to the picture, with the margin around it
	var inner_scale := Vector2(pixels) / (logical_size * (1.0 + 2.0 * MARGIN))
	canvas.margin = logical_size * MARGIN * inner_scale
	viewport.add_child(canvas)
	add_child(viewport)
	_pending[key] = {"viewport": viewport, "frame": frame}
	if not RenderingServer.frame_post_draw.is_connected(_on_frame_post_draw):
		RenderingServer.frame_post_draw.connect(_on_frame_post_draw)
	stats["bake_usec"] += Time.get_ticks_usec() - t0
	return true


## After a frame has been drawn: every bake started in an EARLIER frame has been rendered, so read it back. (One connection serves all.)
func _on_frame_post_draw() -> void:
	var now := Engine.get_process_frames()
	for key in _pending.keys():
		if int(_pending[key]["frame"]) < now:
			_finish_bake(key)
	if _pending.is_empty():
		RenderingServer.frame_post_draw.disconnect(_on_frame_post_draw)


func _finish_bake(key: String) -> void:
	var viewport: SubViewport = _pending[key]["viewport"]
	_pending.erase(key)
	if viewport == null or not is_instance_valid(viewport):
		return
	var t0 := Time.get_ticks_usec()
	var image := viewport.get_texture().get_image() if viewport.is_inside_tree() else null
	viewport.queue_free()
	if image == null or image.is_empty():
		stats["failed"] += 1
		if stats["failed"] >= 3 and stats["baked"] == 0:
			enabled = false   # a renderer that cannot be read back (headless): stop trying, draw live
		return
	var bytes := image.get_data().size()
	if bytes > budget_bytes:
		return
	while _bytes + bytes > budget_bytes and not _order.is_empty():
		_evict_oldest()
	_entries[key] = {"texture": ImageTexture.create_from_image(image), "bytes": bytes}
	_order.append(key)
	_bytes += bytes
	stats["baked"] += 1
	stats["peak_bytes"] = maxi(int(stats["peak_bytes"]), _bytes)
	stats["bake_usec"] += Time.get_ticks_usec() - t0
	baked.emit(key)


func _evict_oldest() -> void:
	var old: String = _order.pop_front()
	_bytes -= int(_entries[old]["bytes"])
	_entries.erase(old)
	stats["evicted"] += 1


func size() -> int:
	return _entries.size()


func bytes_used() -> int:
	return _bytes


## Hits over hits plus misses (0 when nothing was asked yet).
func hit_rate() -> float:
	var total := int(stats["hits"]) + int(stats["misses"])
	return float(stats["hits"]) / float(total) if total > 0 else 0.0


## Frees every baked picture (a game is left or loaded, or memory is needed elsewhere).
func clear() -> void:
	_entries.clear()
	_order.clear()
	_bytes = 0
	for key in _pending:
		if is_instance_valid(_pending[key]["viewport"]):
			(_pending[key]["viewport"] as Node).queue_free()
	_pending.clear()


## Test and tool hook: stores an already rendered image under a key, applying the same budget and eviction as a real bake.
func store_image(key: String, image: Image) -> void:
	var bytes := image.get_data().size()
	if bytes > budget_bytes:
		return
	while _bytes + bytes > budget_bytes and not _order.is_empty():
		_evict_oldest()
	_entries[key] = {"texture": ImageTexture.create_from_image(image), "bytes": bytes}
	_order.append(key)
	_bytes += bytes
	stats["peak_bytes"] = maxi(int(stats["peak_bytes"]), _bytes)
