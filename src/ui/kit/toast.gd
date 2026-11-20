class_name FcToast
extends PanelContainer
## One notification: a coloured edge, an icon and a message. Kinds: INFO, SUCCESS, WARNING, ERROR. Clicking dismisses it.
## FcToastStack shows several at once and removes them after a few seconds (errors stay longer).

signal dismissed

enum Kind { INFO, SUCCESS, WARNING, ERROR }

const COLORS := {Kind.INFO: FcUiTokens.INFO, Kind.SUCCESS: FcUiTokens.SUCCESS, Kind.WARNING: FcUiTokens.WARNING, Kind.ERROR: FcUiTokens.DANGER}
const ICONS := {Kind.INFO: "info", Kind.SUCCESS: "circle-check", Kind.WARNING: "triangle-alert", Kind.ERROR: "circle-alert"}

var kind: Kind
var message: String


func _init(toast_kind: Kind = Kind.INFO, text: String = "") -> void:
	kind = toast_kind
	message = text
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size.x = 340   # a compact card centred in the stack, narrow enough for a phone
	size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(row)
	row.add_child(FcUiIcons.rect(ICONS[kind], COLORS[kind], 20))
	var label := FcUiTables.label(text, FcUiTokens.TYPE_BODY)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = 220
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(label)
	# the style is built here (not looked up) because a theme lookup needs the node to be in the tree already
	var edge := StyleBoxFlat.new()
	edge.bg_color = FcUiTokens.SURFACE_RAISED
	edge.border_color = FcUiTokens.BORDER
	edge.set_border_width_all(1)
	edge.border_width_left = 4
	edge.border_color = COLORS[kind]
	edge.set_corner_radius_all(FcUiTokens.RADIUS_CONTROL)
	edge.content_margin_left = 14
	edge.content_margin_right = 14
	edge.content_margin_top = 10
	edge.content_margin_bottom = 10
	FcUiTokens.elevate(edge, 2)
	add_theme_stylebox_override("panel", edge)
	gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed:
			dismiss())


## How long a toast of this kind stays on screen.
static func hold_seconds(toast_kind: Kind) -> float:
	return 6.0 if toast_kind == Kind.ERROR else 3.0


func dismiss() -> void:
	if is_queued_for_deletion():
		return
	dismissed.emit()
	FcMotion.fade_out(self, FcUiTokens.DUR_BASE, true)   # frees the toast when the fade ends (at once when motion is reduced)
