class_name FcBroadcastOverlay
extends PanelContainer
## The broadcast graphic strip (master plan B2b): one title line and one detail line with a team-coloured edge, shown over the court for
## the most important item of the current event (FcBroadcastGraphics). It only DISPLAYS an item; it decides nothing and holds no game state.
## It never takes the mouse, so the court, the feed and every control underneath still work, and with reduced motion it simply appears.
## The same component sits over the 2D court today and over a 3D viewport later (it is a Control, not part of the court drawing).

var _title := Label.new()
var _detail := Label.new()
var _edge := ColorRect.new()
var _colors: Array = [FcUiTokens.INFO, FcUiTokens.PRIMARY]
var _current: Dictionary = {}


func _init(team_colors: Array = []) -> void:
	name = "BroadcastOverlay"
	if team_colors.size() == 2:
		_colors = team_colors
	theme_type_variation = "ScorePanel"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	visible = false
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", FcUiTokens.SPACE_3)
	add_child(row)
	_edge.custom_minimum_size = Vector2(6, 0)
	_edge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_edge)
	var words := VBoxContainer.new()
	words.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title.theme_type_variation = "HeadingLabel"
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_title.custom_minimum_size.x = 120
	_detail.theme_type_variation = "CaptionLabel"
	_detail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail.custom_minimum_size.x = 120
	words.add_child(_title)
	words.add_child(_detail)
	row.add_child(words)


## Set by the screen's HUD level: when true the strip stays hidden whatever item arrives.
var hud_hidden: bool = false
## When true (Broadcast mode) the strip leaves by itself after the style's hold time, like a television lower third; otherwise it stays until the next item.
var auto_hide: bool = false
var _tween: Tween


## Shows `item` (an FcBroadcastGraphics item), or hides the strip when it is empty.
func show_item(item: Dictionary) -> void:
	_current = item
	if item.is_empty() or hud_hidden:
		visible = false
		return
	_title.text = str(item["title"])
	_detail.text = str(item["detail"])
	_detail.visible = _detail.text != ""
	var side := int(item["side"])
	_edge.color = _colors[side] if side >= 0 else FcUiTokens.STEEL
	if FcBroadcastStyle.gold_kinds().has(str(item["kind"])):
		_edge.color = FcUiTokens.GOLD   # runs, milestones, clutch time and the final get the gold edge
	visible = true
	var timing := FcBroadcastStyle.timing("lower_third", FcMotion.reduced)
	if _tween != null and _tween.is_valid():
		_tween.kill()
	modulate.a = 1.0
	if not is_inside_tree() or (timing["in"] <= 0.0 and not auto_hide):
		return
	_tween = create_tween()   # fade in over the style's `in` time, then (Broadcast mode only) hold and fade out like a television lower third
	if timing["in"] > 0.0:
		modulate.a = 0.0
		_tween.tween_property(self, "modulate:a", 1.0, timing["in"])
	if auto_hide:
		_tween.tween_interval(timing["hold"])
		_tween.tween_property(self, "modulate:a", 0.0, maxf(timing["out"], 0.001))
		_tween.tween_callback(func() -> void: visible = false)


## What the strip shows now: "Title | detail" (empty when hidden). Used by tests and screen readers.
func summary() -> String:
	if not visible or _current.is_empty():
		return ""
	return "%s | %s" % [_title.text, _detail.text] if _detail.text != "" else _title.text


func current_item() -> Dictionary:
	return _current
