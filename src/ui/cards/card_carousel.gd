class_name FcCardCarousel
extends Control
## Browses cards one at a time: the focused card in the middle, large, with its neighbours smaller and dimmer on each side. Left and
## right (keys, controller, the arrow buttons, the mouse wheel, or a swipe) slide to the next card; clicking a neighbour brings it to the
## middle; clicking or pressing accept on the middle card emits `activated` (the screen opens the inspector). Only a handful of card nodes
## exist (a pool reused as the carousel slides), so a collection of any size costs the same.
## Emits focused(index) whenever the focused card changes and activated(index) for the middle card.

signal focused(index: int)
signal activated(index: int)

const POOL := 9
const VISIBLE_RANGE := 3.0
const SWIPE_DISTANCE := 60.0

var rows: Array = []
var index: int = 0
var card_size: Vector2 = FcCardFace.SIZE_DETAIL
## Called with a row to get that card's options (tag, caption...); the result is passed to FcCardFace.setup.
var options_for: Callable = Callable()
## The fractional position being shown (animated between cards).
var position_index: float = 0.0:
	set(v):
		position_index = v
		_layout()
var _cards: Array[FcCardFace] = []
var _drag: float = 0.0
var _tween: Tween = null
var _prev: FcButton
var _next: FcButton
var _counter := Label.new()


func _init() -> void:
	focus_mode = Control.FOCUS_ALL
	clip_contents = false
	for i in POOL:
		var card := FcCardFace.new()
		card.focus_mode = Control.FOCUS_NONE   # the carousel itself takes focus; arrows move between cards
		card.visible = false
		card.set_meta("slot", i)
		card.activated.connect(func() -> void: _card_pressed(card))
		add_child(card)
		_cards.append(card)
	_prev = FcButton.icon_only("chevron-left", "Previous card", func() -> void: step(-1))
	_next = FcButton.icon_only("chevron-right", "Next card", func() -> void: step(1))
	_counter.theme_type_variation = "MutedLabel"
	_counter.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	for c in [_prev, _next, _counter]:
		add_child(c)
	resized.connect(_layout)
	custom_minimum_size = Vector2(300, card_size.y + 70)


func set_rows(new_rows: Array, start: int = 0) -> void:
	rows = new_rows
	index = clampi(start, 0, maxi(0, rows.size() - 1))
	position_index = float(index)
	for c in _cards:
		c.set_meta("row_id", "")
	_layout()


## Moves the focus by `delta` cards (animated; instant when motion is reduced).
func step(delta: int) -> void:
	go_to(index + delta)


func go_to(target: int, animate: bool = true) -> void:
	if rows.is_empty():
		return
	target = clampi(target, 0, rows.size() - 1)
	if target == index and is_equal_approx(position_index, float(target)):
		return
	var changed := target != index
	index = target
	if _tween != null and _tween.is_valid():
		_tween.kill()
	if animate:
		_tween = FcMotion.tween_property(self, "position_index", float(target), FcUiTokens.DUR_BASE + 0.04)
	else:
		position_index = float(target)
	if changed:
		focused.emit(index)


func focused_row() -> Dictionary:
	return rows[index] if index >= 0 and index < rows.size() else {}


## The card nodes that are showing something right now (the middle one and up to three each side).
func visible_card_count() -> int:
	var n := 0
	for c in _cards:
		if c.visible:
			n += 1
	return n


func _gui_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_left"):
		step(-1)
		accept_event()
	elif event.is_action_pressed("ui_right"):
		step(1)
		accept_event()
	elif event.is_action_pressed("ui_accept") and not rows.is_empty():
		activated.emit(index)
		accept_event()
	elif event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_LEFT]:
		step(-1)
		accept_event()
	elif event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_DOWN, MOUSE_BUTTON_WHEEL_RIGHT]:
		step(1)
		accept_event()
	elif event is InputEventScreenDrag or (event is InputEventMouseMotion and event.button_mask & MOUSE_BUTTON_MASK_LEFT != 0):
		_drag += event.relative.x
		if absf(_drag) >= SWIPE_DISTANCE:
			step(-1 if _drag > 0.0 else 1)   # dragging right shows the previous card
			_drag = 0.0
		accept_event()
	elif event is InputEventMouseButton and not event.pressed:
		_drag = 0.0


func _card_pressed(card: FcCardFace) -> void:
	var idx: int = card.get_meta("idx", -1)
	if idx == index:
		activated.emit(index)
	elif idx >= 0:
		go_to(idx)


func _layout() -> void:
	if _cards.is_empty():
		return
	var buttons_y := size.y - 44.0
	var counter_h := 24.0
	_prev.position = Vector2(size.x / 2.0 - 120.0, buttons_y)
	_next.position = Vector2(size.x / 2.0 + 120.0 - _next.size.x, buttons_y)
	_counter.size = Vector2(160, counter_h)
	_counter.position = Vector2(size.x / 2.0 - 80.0, buttons_y + 8.0)
	_prev.disabled = rows.is_empty() or index <= 0
	_next.disabled = rows.is_empty() or index >= rows.size() - 1
	_counter.text = "%d of %d" % [index + 1, rows.size()] if not rows.is_empty() else "No cards"
	var base := int(roundf(position_index))
	var free_slot := 0
	var used := {}
	# keep cards that already show a visible row where they are; give the others to free nodes
	for c in _cards:
		c.visible = false
	var wanted: Array[int] = []
	for k in range(-int(VISIBLE_RANGE), int(VISIBLE_RANGE) + 1):
		var idx := base + k
		if idx >= 0 and idx < rows.size() and absf(idx - position_index) <= VISIBLE_RANGE + 0.5:
			wanted.append(idx)
	for idx in wanted:
		var card := _card_for(idx, used)
		var d := float(idx) - position_index
		var sc := clampf(1.0 - 0.16 * absf(d), 0.5, 1.0)
		var step_x := card_size.x * 0.68
		var x := size.x / 2.0 + d * step_x * (1.0 if absf(d) < 1.0 else 1.0)
		var h := card_size.y
		card.size = card_size
		card.pivot_offset = card_size / 2.0
		card.scale = Vector2(sc, sc)
		card.position = Vector2(x - card_size.x / 2.0, maxf(0.0, (size.y - 56.0 - h) / 2.0))
		# neighbours darken instead of fading, so overlapping cards never show through each other
		var shade := clampf(1.0 - 0.22 * absf(d), 0.3, 1.0) * (1.0 if bool(rows[idx].get("owned", true)) else 0.65)
		card.modulate = Color(shade, shade, shade, 1.0)
		card.z_index = 10 - int(absf(d) * 3.0)
		card.visible = true
		card.inspected = absf(d) < 0.5
		free_slot += 1


## A pooled card node showing row `idx` (reusing the node that already shows it when there is one).
func _card_for(idx: int, used: Dictionary) -> FcCardFace:
	for c in _cards:
		if c.get_meta("idx", -1) == idx and not used.has(c):
			used[c] = true
			return c
	for c in _cards:
		if not used.has(c) and not c.visible:
			used[c] = true
			c.set_meta("idx", idx)
			var options: Dictionary = options_for.call(rows[idx]) if options_for.is_valid() else {}
			options["size"] = card_size
			c.setup(rows[idx], options)
			c.pivot_offset = card_size / 2.0
			return c
	return _cards[0]
