class_name FcProductionPanel
extends PanelContainer
## Draws a broadcast production (Broadcast pass 2, M7): one segment at a time, with Previous, Next, an auto-advance switch that follows each
## segment's own length, and a Close button. It shows what FcProductionPlan or FcWeeklyRecap built and decides nothing; the same panel serves the
## replay screen's shows (pregame, halftime, postgame, championship) and the Owner's weekly "Full Court Tonight". Driven by `advance(delta)` for the
## auto-advance, so a test needs no real time. A segment that cannot be built from the data says why instead of showing nothing.

## The width of a table's first column (names), so they do not wrap letter by letter.
const FIRST_COLUMN_WIDTH := 240.0

signal closed
## The highlights segment's "Play the reel" button: the screen runs the reel for these references.
signal reel_requested(refs: Array)

var plan: Dictionary = {}
var segment_index: int = 0
var auto: bool = false

var _title := Label.new()
var _progress := Label.new()
var _heading := Label.new()
var _body := VBoxContainer.new()
var _prev: Button
var _next: Button
var _auto_button: Button
var _timer: float = 0.0


func _init() -> void:
	name = "ProductionPanel"
	theme_type_variation = "ScorePanel"
	visible = false
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", FcUiTokens.SPACE_2)
	add_child(root)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", FcUiTokens.SPACE_3)
	_title.theme_type_variation = "HeadingLabel"
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_title)
	_progress.theme_type_variation = "CaptionLabel"
	head.add_child(_progress)
	head.add_child(FcButton.make("Close", FcButton.Variant.GHOST, close))
	root.add_child(head)
	_heading.theme_type_variation = "HeadingLabel"
	root.add_child(_heading)
	_body.add_theme_constant_override("separation", FcUiTokens.SPACE_1)
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(_body)
	var nav := HFlowContainer.new()
	nav.add_theme_constant_override("h_separation", FcUiTokens.SPACE_2)
	set_process(true)
	_prev = FcButton.make("Previous", FcButton.Variant.SECONDARY, previous)
	_next = FcButton.make("Next", FcButton.Variant.PRIMARY, next)
	_auto_button = FcButton.make("Auto: off", FcButton.Variant.GHOST, func() -> void: set_auto(not auto))
	for b in [_prev, _next, _auto_button]:
		nav.add_child(b)
	root.add_child(nav)


## Shows a plan (FcProductionPlan.build or FcWeeklyRecap.build) from its first segment. An empty plan hides the panel.
func show_plan(new_plan: Dictionary, autoplay: bool = false) -> void:
	plan = new_plan
	segment_index = 0
	_timer = 0.0
	if plan.is_empty():
		visible = false
		return
	visible = true
	_title.text = str(plan["title"])
	set_auto(autoplay)
	_render()


func segment_count() -> int:
	return (plan.get("segments", []) as Array).size()


func current_segment() -> Dictionary:
	return (plan["segments"] as Array)[segment_index] if segment_count() > 0 else {}


func next() -> void:
	if segment_index + 1 < segment_count():
		segment_index += 1
		_timer = 0.0
		_render()
	elif auto:
		set_auto(false)   # the last segment: stay on it


func previous() -> void:
	if segment_index > 0:
		segment_index -= 1
		_timer = 0.0
		_render()


func set_auto(on: bool) -> void:
	auto = on
	_auto_button.text = "Auto: on" if on else "Auto: off"
	_timer = 0.0


func close() -> void:
	visible = false
	set_auto(false)
	closed.emit()


func _process(delta: float) -> void:
	advance(delta)


## Real seconds pass: in auto mode each segment stays up for its own length, then the next one comes.
func advance(delta: float) -> void:
	if not visible or not auto or segment_count() == 0:
		return
	_timer += delta
	if _timer >= float(current_segment()["seconds"]):
		next()


func _render() -> void:
	for c in _body.get_children():
		_body.remove_child(c)
		c.queue_free()
	var seg := current_segment()
	if seg.is_empty():
		return
	_progress.text = "%d of %d" % [segment_index + 1, segment_count()]
	_heading.text = str(seg["title"])
	_prev.disabled = segment_index == 0
	_next.disabled = segment_index + 1 >= segment_count()
	if not bool(seg["available"]):
		_body.add_child(_line(str(seg["note"]), true))
		return
	var rows: Array = seg["rows"]
	if not rows.is_empty():
		var columns := 0
		for r in rows:
			columns = maxi(columns, (r as Array).size())
		var grid := GridContainer.new()
		grid.name = "SegmentRows"
		grid.columns = maxi(1, columns)
		grid.add_theme_constant_override("h_separation", FcUiTokens.SPACE_4)
		grid.add_theme_constant_override("v_separation", FcUiTokens.SPACE_1)
		grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		for r in rows:
			for col in columns:
				var l := _line(str((r as Array)[col]) if col < (r as Array).size() else "", false)
				l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
				l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				if col == 0 and columns >= 3:
					l.custom_minimum_size.x = FIRST_COLUMN_WIDTH   # team and player names read on one line
				grid.add_child(l)
		_body.add_child(grid)
	for text in seg["lines"]:
		_body.add_child(_line(str(text), false))
	if str(seg["type"]) == "highlights" and not ((seg["facts"] as Dictionary).get("refs", []) as Array).is_empty():
		var refs: Array = (seg["facts"] as Dictionary)["refs"]
		_body.add_child(FcButton.make("Play the highlight reel", FcButton.Variant.PRIMARY, func() -> void: reel_requested.emit(refs)))
	if str(seg.get("note", "")) != "":
		_body.add_child(_line(str(seg["note"]), true))


func _line(text: String, muted: bool) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 80
	if muted:
		l.theme_type_variation = "MutedLabel"
	return l


## The text of the segment now shown, flattened (tests and screen readers): title, rows joined by " | ", then lines.
func summary() -> String:
	var seg := current_segment()
	if seg.is_empty() or not visible:
		return ""
	var parts: Array[String] = [str(seg["title"])]
	if not bool(seg["available"]):
		parts.append(str(seg["note"]))
	else:
		for r in seg["rows"]:
			parts.append(" | ".join((r as Array).map(func(c) -> String: return str(c))))
		for l in seg["lines"]:
			parts.append(str(l))
	return "\n".join(parts)
