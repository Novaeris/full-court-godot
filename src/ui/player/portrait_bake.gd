class_name FcPortraitBake
extends Node
## PROTOTYPE (docs/PLAYER_VISUAL_PROPOSAL.md, section 6): draws a player figure ONCE into a small off-screen viewport and hands out its
## texture, so a roster, a collection grid or a card list pays the figure's drawing cost one time per (player, size, crop) instead of on every
## redraw (a scroll, a resize, a hover animation). The high-fidelity figure costs about 1 to 2 ms per portrait to draw (tools/portrait_bench.gd);
## a baked portrait is a single textured rectangle.
## Rules: the picture is whatever FcPlayerFigure draws for the same resolved visual, so the same player is the same face; the cache key holds
## everything that changes the picture (key, age, team colours, number, crop, size, which figure), so a new season (age) or a trade (colours)
## makes a new picture and a stale one is never shown; the cache is bounded (least recently used pictures are freed); it holds pictures only,
## never game data. Add one instance to the scene tree (FcApp owns it) and set `shared`.

## How many pictures to keep (about 64 KB each at 128 px).
var max_entries: int = 320

static var shared: FcPortraitBake = null

var _entries: Dictionary = {}   # key -> {viewport: SubViewport, texture: Texture2D}
var _order: Array = []          # least recently used first
var stats := {"hits": 0, "misses": 0, "evicted": 0}


class _Canvas extends Control:
	var visual: Dictionary = {}
	var crop := "bust"

	func _draw() -> void:
		if crop == "head":
			FcPlayerFigure.draw_headshot(self, Rect2(Vector2(size.x * 0.04, size.y * 0.04), size * 0.92), visual)
		elif crop == "full":
			FcPlayerFigure.draw(self, Rect2(Vector2.ZERO, size), visual, true)
		else:
			FcPlayerFigure.draw(self, Rect2(Vector2(size.x * 0.06, size.y * 0.1), size * Vector2(0.88, 0.9)), visual)


func _enter_tree() -> void:
	if shared == null:
		shared = self


func _exit_tree() -> void:
	if shared == self:
		shared = null


## Everything that changes the picture, as one text key.
static func cache_key(visual: Dictionary, pixels: Vector2i, crop: String) -> String:
	var uniform: Dictionary = visual.get("uniform", {})
	var id: Dictionary = visual.get("identity", {})
	return "%s|t%d|age%d|%s|%s|n%d|%s|%dx%d|hd%d|%s%s%s%s" % [visual.get("key", ""), int(visual.get("tier", 2)), int(visual.get("age", 0)), (uniform.get("primary", Color.BLACK) as Color).to_html(false),
		(uniform.get("secondary", Color.BLACK) as Color).to_html(false), int(uniform.get("number", 0)), crop, pixels.x, pixels.y, 1 if FcPlayerFigure.hd_enabled else 0,
		id.get("skin", ""), id.get("hair", ""), id.get("face", ""), id.get("facial_hair", "")]


## The baked texture of a visual (rendered on the next frame; until then it is blank, so callers may draw the live figure for one frame).
func texture_for(visual: Dictionary, pixels: Vector2i, crop: String = "bust") -> Texture2D:
	var key := cache_key(visual, pixels, crop)
	if _entries.has(key):
		stats["hits"] += 1
		_order.erase(key)
		_order.append(key)
		return _entries[key]["texture"]
	stats["misses"] += 1
	var viewport := SubViewport.new()
	viewport.size = pixels
	viewport.transparent_bg = true
	viewport.disable_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	var canvas := _Canvas.new()
	canvas.visual = visual
	canvas.crop = crop
	canvas.size = Vector2(pixels)
	viewport.add_child(canvas)
	add_child(viewport)
	_entries[key] = {"viewport": viewport, "texture": viewport.get_texture()}
	_order.append(key)
	while _order.size() > max_entries:
		var old: String = _order.pop_front()
		var entry: Dictionary = _entries[old]
		(entry["viewport"] as SubViewport).queue_free()
		_entries.erase(old)
		stats["evicted"] += 1
	return _entries[key]["texture"]


func size() -> int:
	return _entries.size()


## Frees every baked picture (after a skin or art change, or to release memory).
func clear() -> void:
	for key in _entries:
		(_entries[key]["viewport"] as SubViewport).queue_free()
	_entries.clear()
	_order.clear()
