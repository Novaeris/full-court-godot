class_name FcPlayerSpotlight
extends PanelContainer
## The player spotlight card (Broadcast pass 2, M2): number, name, position and a running stat line, shown over the stage for the player an
## event is about (FcSpotlightModel). It only DISPLAYS a model; it decides nothing. Timings come from FcBroadcastStyle, it never takes the
## mouse, and with reduced motion it simply appears. In Broadcast mode (`auto_hide`) it leaves after the style's hold time.

var hud_hidden: bool = false
var auto_hide: bool = false

var _number := Label.new()
var _name := Label.new()
var _stats := Label.new()
var _edge := ColorRect.new()
var _colors: Array = [FcUiTokens.INFO, FcUiTokens.PRIMARY]
var _current: Dictionary = {}
var _tween: Tween


func _init(team_colors: Array = []) -> void:
	name = "PlayerSpotlight"
	if team_colors.size() == 2:
		_colors = team_colors
	theme_type_variation = "ScorePanel"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size_flags_horizontal = Control.SIZE_SHRINK_END
	visible = false
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", FcUiTokens.SPACE_3)
	add_child(row)
	_edge.custom_minimum_size = Vector2(FcUiTokens.SPACE_1, 0)
	_edge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_edge)
	_number.theme_type_variation = "DisplayLabel"
	_number.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_number)
	var words := VBoxContainer.new()
	words.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_name.theme_type_variation = "HeadingLabel"
	_name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stats.theme_type_variation = "CaptionLabel"
	_stats.mouse_filter = Control.MOUSE_FILTER_IGNORE
	words.add_child(_name)
	words.add_child(_stats)
	row.add_child(words)


## Shows an FcSpotlightModel result, or hides the card when it is empty.
func show_model(model: Dictionary) -> void:
	_current = model
	if model.is_empty() or hud_hidden:
		visible = false
		return
	_number.text = "#%d" % int(model["number"]) if int(model["number"]) > 0 else ""
	_number.visible = _number.text != ""
	_name.text = "%s  %s" % [str(model["name"]), str(model["position"])]
	_stats.text = FcSpotlightModel.stat_text(model)
	_edge.color = _colors[int(model["side"])] if int(model["side"]) in [0, 1] else FcUiTokens.STEEL
	visible = true
	var timing := FcBroadcastStyle.timing("spotlight", FcMotion.reduced)
	if _tween != null and _tween.is_valid():
		_tween.kill()
	modulate.a = 1.0
	if not is_inside_tree() or (timing["in"] <= 0.0 and not auto_hide):
		return
	_tween = create_tween()
	if timing["in"] > 0.0:
		modulate.a = 0.0
		_tween.tween_property(self, "modulate:a", 1.0, timing["in"])
	if auto_hide:
		_tween.tween_interval(timing["hold"])
		_tween.tween_property(self, "modulate:a", 0.0, maxf(timing["out"], 0.001))
		_tween.tween_callback(func() -> void: visible = false)


## "#9  E. Herrera  SG | 12 PTS  ·  4 REB  ·  3 AST" (empty when hidden); used by tests.
func summary() -> String:
	if not visible or _current.is_empty():
		return ""
	return "%s | %s" % [_name.text, _stats.text]


func current_model() -> Dictionary:
	return _current
