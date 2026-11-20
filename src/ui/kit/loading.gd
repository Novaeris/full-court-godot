class_name FcLoading
extends VBoxContainer
## A loading indicator: a rotating arc and a message ("Simulating the season..."). When motion is reduced the arc is still (and
## the message carries the meaning). It stops animating when hidden. FcLoadingOverlay puts one over a whole screen.

var message_label: Label
var _spinner := _Spinner.new()


func _init(message: String = "Loading...") -> void:
	alignment = BoxContainer.ALIGNMENT_CENTER
	add_theme_constant_override("separation", FcUiTokens.SPACE_3)
	_spinner.custom_minimum_size = Vector2(40, 40)
	_spinner.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	add_child(_spinner)
	message_label = FcUiTables.label(message, FcUiTokens.TYPE_BODY)
	message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(message_label)


func set_message(text: String) -> void:
	message_label.text = text


## The arc itself.
class _Spinner extends Control:
	var _angle := 0.0

	func _process(delta: float) -> void:
		if not FcMotion.reduced and is_visible_in_tree():
			_angle = fmod(_angle + delta * 5.0, TAU)
			queue_redraw()

	func _draw() -> void:
		var center := size / 2.0
		var radius := minf(size.x, size.y) / 2.0 - 3.0
		draw_arc(center, radius, 0.0, TAU, 48, FcUiTokens.BORDER, 4.0, true)
		draw_arc(center, radius, _angle, _angle + PI * 0.7, 24, FcUiTheme.accent, 4.0, true)
