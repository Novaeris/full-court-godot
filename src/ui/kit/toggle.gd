class_name FcToggle
extends CheckButton
## An on/off switch with its label ("Reduce motion"). `toggled(on)` is the stock Godot signal. States come from the theme
## (hover, focus, pressed, disabled).


func _init() -> void:
	focus_mode = Control.FOCUS_ALL
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND


func _ready() -> void:
	custom_minimum_size.y = FcUiTokens.min_target()


static func make(label: String, on: bool = false, on_toggle: Callable = Callable()) -> FcToggle:
	var t := FcToggle.new()
	t.text = label
	t.set_pressed_no_signal(on)
	if on_toggle.is_valid():
		t.toggled.connect(on_toggle)
	return t
