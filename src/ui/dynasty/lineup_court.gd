class_name FcLineupCourt
extends Control
## The five starters standing on a half court: the point guard at the top of the key, the wings out wide, the power forward on the block
## and the center under the basket. Tap (or click) a player's card to choose someone else for that slot. It only POSITIONS the slot
## widgets the screen gives it (one per starter slot, in roster order PG, SG, SF, PF, C) and draws the court behind them; choosing a
## player is done by the screen through the controller. The court is as wide as the space it gets (a phone or a desktop panel).

## Where each starter stands, as a fraction of the court (x across, y down; the basket is at the top).
const SPOTS := [Vector2(0.50, 0.87), Vector2(0.83, 0.64), Vector2(0.17, 0.64), Vector2(0.81, 0.33), Vector2(0.50, 0.15)]

var _slots: Array[Control] = []


func _init() -> void:
	custom_minimum_size = Vector2(300, 580)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	resized.connect(_layout)


## `widgets` are the five slot widgets in roster order.
func set_slots(widgets: Array) -> void:
	for w in _slots:
		remove_child(w)
		w.queue_free()
	_slots.clear()
	for w in widgets:
		add_child(w)
		_slots.append(w)
	_layout()


func slot_count() -> int:
	return _slots.size()


const MAX_WIDTH := 560.0


## The court is as wide as the space (a phone) but never wider than MAX_WIDTH on a big screen, and sits in the middle.
func _court_width() -> float:
	return minf(size.x, MAX_WIDTH)


func _layout() -> void:
	var cw := _court_width()
	var ox := (size.x - cw) / 2.0
	custom_minimum_size.y = maxf(580.0, cw)
	for i in _slots.size():
		var w := _slots[i]
		var spot: Vector2 = SPOTS[mini(i, SPOTS.size() - 1)]
		var wsize := w.get_combined_minimum_size()
		w.size = wsize
		w.position = Vector2(ox + spot.x * cw - wsize.x / 2.0, spot.y * size.y - wsize.y / 2.0).clamp(Vector2(ox, 0.0), Vector2(maxf(ox, ox + cw - wsize.x), maxf(0.0, size.y - wsize.y)))
	queue_redraw()


## A colour at a given opacity (the court lines and floor are the theme colours, softened).
static func _alpha(c: Color, a: float) -> Color:
	var out := c
	out.a = a
	return out


func _draw() -> void:
	var line := _alpha(FcUiTokens.BORDER, 0.9)
	var w := _court_width()
	var h := size.y
	draw_set_transform(Vector2((size.x - w) / 2.0, 0.0), 0.0, Vector2.ONE)
	draw_rect(Rect2(0, 0, w, h), _alpha(FcUiTokens.SURFACE, 0.55))
	draw_rect(Rect2(1, 1, w - 2, h - 2), line, false, 2.0)
	# the key, the free-throw circle, the three-point arc and the basket
	var key_w := w * 0.34
	draw_rect(Rect2((w - key_w) / 2.0, 0, key_w, h * 0.42), line, false, 2.0)
	draw_arc(Vector2(w / 2.0, h * 0.42), key_w / 2.0, 0.0, PI, 32, line, 2.0, true)
	draw_arc(Vector2(w / 2.0, h * 0.05), w * 0.46, 0.15 * PI, 0.85 * PI, 40, line, 2.0, true)
	draw_circle(Vector2(w / 2.0, h * 0.06), 7.0, _alpha(FcUiTheme.accent, 0.8))
	draw_line(Vector2(w / 2.0 - 22, h * 0.03), Vector2(w / 2.0 + 22, h * 0.03), _alpha(FcUiTheme.accent, 0.8), 3.0)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
