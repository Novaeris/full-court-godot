class_name FcSplash
extends Control
## The startup sequence: the Novaeris logo, then the Full Court logo, on the brand navy, then it is gone and the main menu (already built
## behind it) shows. Any key, click or touch skips it. With reduced motion there are no fades: each logo simply shows for a moment.
## It only ever PRESENTS: it starts nothing and loads nothing, so skipping it is always safe.

signal finished

const HOLD := 1.1
const FADE := 0.45
const WIDTH_FRACTION := 0.5

var _logo := TextureRect.new()
var _step := 0
var _done := false


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	var bg := ColorRect.new()
	bg.color = FcUiTokens.BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	_logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_logo.modulate.a = 0.0
	add_child(_logo)


## True when the logos exist (without them there is nothing to show and the splash is skipped).
static func can_show() -> bool:
	return FcBrand.has(FcBrand.NOVAERIS) and FcBrand.has(FcBrand.FULL_COURT)


func start() -> void:
	grab_focus()
	_show_step()


func _show_step() -> void:
	if _done:
		return
	var ids := [FcBrand.NOVAERIS, FcBrand.FULL_COURT]
	if _step >= ids.size():
		_finish()
		return
	var width := maxi(220, int(minf(size.x, 1920.0) * WIDTH_FRACTION))
	var tex := FcBrand.texture(ids[_step], width)
	_logo.texture = tex
	var ratio := float(tex.get_height()) / float(tex.get_width())
	_logo.size = Vector2(width, width * ratio)
	_logo.position = (size - _logo.size) / 2.0
	_logo.modulate.a = 1.0 if FcMotion.reduced else 0.0
	var hold := HOLD if _step == 0 else HOLD * 0.9
	if not is_inside_tree():
		_next_step()
		return
	if FcMotion.reduced:
		get_tree().create_timer(hold * 0.8).timeout.connect(_next_step)
		return
	var tw := create_tween()
	tw.tween_property(_logo, "modulate:a", 1.0, FADE)
	tw.tween_interval(hold)
	if _step == 1:
		tw.tween_callback(_finish)   # the Full Court logo leaves with the whole splash fading out
	else:
		tw.tween_property(_logo, "modulate:a", 0.0, FADE)
		tw.tween_callback(_next_step)


func _next_step() -> void:
	_step += 1
	_show_step()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed or event is InputEventMouseButton and event.pressed or event is InputEventScreenTouch and event.pressed:
		accept_event()
		_finish()


func _finish() -> void:
	if _done:
		return
	_done = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	finished.emit()
	if not is_inside_tree():
		return
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, FcMotion.duration(FADE, true))
	tw.tween_callback(queue_free)
