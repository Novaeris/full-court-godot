class_name FcModal
extends Control
## A dialog over a dimmed screen: info (one OK button), confirm (confirm and cancel) or destructive (the confirm button is red
## and focus starts on Cancel, so Enter cannot delete by accident). Escape (ui_cancel) cancels; clicking the dim area cancels
## when `dismissible`. Focus starts on a button and returns to where it was when the dialog closes. Extra content goes into `content`.
## Signals: confirmed, cancelled, closed (always after either). The Phase 3 shell will stack modals; this is the component.

signal confirmed
signal cancelled
signal closed

enum Kind { INFO, CONFIRM, DESTRUCTIVE }

var kind: Kind = Kind.INFO
var dismissible: bool = true
var panel: FcPanel
var content: VBoxContainer
var confirm_button: FcButton
var cancel_button: FcButton
var _scrim := ColorRect.new()
var _return_focus: Control = null
var _closing := false


func _init(title: String = "", text: String = "", modal_kind: Kind = Kind.INFO, confirm_text: String = "OK", cancel_text: String = "Cancel") -> void:
	kind = modal_kind
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_scrim.color = FcUiTokens.SCRIM
	_scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	_scrim.gui_input.connect(_on_scrim_input)
	add_child(_scrim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	panel = FcPanel.new(title, FcPanel.Variant.MODAL)
	panel.custom_minimum_size.x = 360
	center.add_child(panel)
	if text != "":
		var body := FcUiTables.label(text, FcUiTokens.TYPE_BODY)
		body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		body.custom_minimum_size.x = 320
		panel.add(body)
	content = VBoxContainer.new()
	panel.add(content)
	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_END
	panel.add(actions)
	if kind != Kind.INFO:
		cancel_button = FcButton.make(cancel_text, FcButton.Variant.SECONDARY, func() -> void: close(false))
		actions.add_child(cancel_button)
	confirm_button = FcButton.make(confirm_text, FcButton.Variant.DESTRUCTIVE if kind == Kind.DESTRUCTIVE else FcButton.Variant.PRIMARY, func() -> void: close(true))
	actions.add_child(confirm_button)


## A confirmation dialog shown on `parent`; `on_confirm` runs only if the player confirms.
static func confirm(parent: Node, title: String, text: String, on_confirm: Callable, destructive: bool = false, confirm_text: String = "Confirm") -> FcModal:
	var m := FcModal.new(title, text, Kind.DESTRUCTIVE if destructive else Kind.CONFIRM, confirm_text)
	m.confirmed.connect(on_confirm)
	m.open(parent)
	return m


## A message with a single OK button.
static func notice(parent: Node, title: String, text: String) -> FcModal:
	var m := FcModal.new(title, text, Kind.INFO)
	m.open(parent)
	return m


## Shows the dialog on `parent` (any Control or Node under the screen) and moves focus into it.
func open(parent: Node) -> void:
	var viewport := parent.get_viewport()
	if viewport != null:
		_return_focus = viewport.gui_get_focus_owner()
	parent.add_child(self)
	FcMotion.fade_in(_scrim)
	FcMotion.pop_in(panel)
	var first: Control = cancel_button if kind == Kind.DESTRUCTIVE else confirm_button
	first.grab_focus.call_deferred()


## Closes the dialog: `accepted` true emits confirmed, false emits cancelled; then closed, and the dialog fades away.
func close(accepted: bool) -> void:
	if _closing:
		return
	_closing = true
	if accepted:
		confirmed.emit()
	else:
		cancelled.emit()
	closed.emit()
	if _return_focus != null and is_instance_valid(_return_focus) and _return_focus.is_inside_tree():
		_return_focus.grab_focus()
	FcMotion.fade_out(self, FcUiTokens.DUR_FAST, true)   # frees the dialog when the fade ends (at once when motion is reduced)


func _unhandled_input(event: InputEvent) -> void:
	if is_inside_tree() and not _closing and event.is_action_pressed("ui_cancel") and (dismissible or kind == Kind.INFO):
		close(kind == Kind.INFO)
		get_viewport().set_input_as_handled()


func _on_scrim_input(event: InputEvent) -> void:
	if dismissible and event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		close(false)
