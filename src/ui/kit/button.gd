class_name FcButton
extends Button
## The game's button, in five variants: PRIMARY (the one main action of a screen), SECONDARY (the default), DESTRUCTIVE (deletes
## or cannot be undone), GHOST (quiet, no fill) and ICON (a square button holding only an icon).
## States: default, hover, focus, pressed, disabled come from the theme; `loading` (disabled, shows a working message) is here.
## Pressing gives a small scale feedback through FcMotion (instant when motion is reduced).

enum Variant { PRIMARY, SECONDARY, DESTRUCTIVE, GHOST, ICON }

const VARIATIONS := {
	Variant.PRIMARY: "PrimaryButton", Variant.SECONDARY: "", Variant.DESTRUCTIVE: "DangerButton",
	Variant.GHOST: "GhostButton", Variant.ICON: "IconButton",
}

var variant: Variant = Variant.SECONDARY:
	set(value):
		variant = value
		_refresh()
## The name of a Lucide icon (see FcUiIcons), or "".
var icon_name: String = "":
	set(value):
		icon_name = value
		_refresh()
## Loading: the button is disabled and shows `loading_text` until loading is turned off again.
var loading: bool = false:
	set(value):
		if value == loading:
			return
		loading = value
		if loading:
			_rest_text = text
			_was_disabled = disabled
			text = loading_text
			disabled = true
		else:
			text = _rest_text
			disabled = _was_disabled
		_refresh()
var loading_text: String = "Working..."
var _rest_text: String = ""
var _was_disabled: bool = false


func _init() -> void:
	focus_mode = Control.FOCUS_ALL
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button_down.connect(_on_down)


## A ready button. `on_press` is connected to `pressed`; `icon_name` is optional.
static func make(label: String, button_variant: Variant = Variant.SECONDARY, on_press: Callable = Callable(), icon: String = "") -> FcButton:
	var b := FcButton.new()
	b.text = label
	b.variant = button_variant
	b.icon_name = icon
	if on_press.is_valid():
		b.pressed.connect(on_press)
	return b


## An icon-only button (give it a tooltip: it has no visible text).
static func icon_only(icon: String, tooltip: String, on_press: Callable = Callable()) -> FcButton:
	var b := make("", Variant.ICON, on_press, icon)
	b.tooltip_text = tooltip
	return b


func _ready() -> void:
	_refresh()


func _refresh() -> void:
	theme_type_variation = VARIATIONS[variant]
	icon = FcUiIcons.texture("loader" if loading else icon_name)
	expand_icon = false
	custom_minimum_size.y = FcUiTokens.min_target()
	if variant == Variant.ICON:
		custom_minimum_size.x = FcUiTokens.min_target()


func _on_down() -> void:
	FcMotion.press(self)
