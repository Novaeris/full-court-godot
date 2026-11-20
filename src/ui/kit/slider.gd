class_name FcSlider
extends HBoxContainer
## A slider with a live value readout ("70%"). Emits value_changed(value). `set_value_silent` changes it without emitting
## (use it when restoring a saved setting). `disabled` greys it out. Keyboard and controller: arrows change the value.

signal value_changed(value: float)

var slider := HSlider.new()
var readout := Label.new()
var suffix: String = ""
var disabled: bool = false:
	set(v):
		disabled = v
		slider.editable = not v


func _init(min_value: float = 0.0, max_value: float = 100.0, step: float = 1.0, unit_suffix: String = "") -> void:
	suffix = unit_suffix
	slider.min_value = min_value
	slider.max_value = max_value
	slider.step = step
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.focus_mode = Control.FOCUS_ALL
	slider.custom_minimum_size = Vector2(120, FcUiTokens.min_target())
	readout.custom_minimum_size.x = 56
	readout.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	readout.theme_type_variation = "NumericLabel"
	add_child(slider)
	add_child(readout)
	slider.value_changed.connect(func(v: float) -> void:
		_show(v)
		value_changed.emit(v))
	_show(slider.value)


func set_value_silent(v: float) -> void:
	slider.set_value_no_signal(v)
	_show(v)


func value() -> float:
	return slider.value


func _show(v: float) -> void:
	readout.text = "%d%s" % [roundi(v), suffix]
