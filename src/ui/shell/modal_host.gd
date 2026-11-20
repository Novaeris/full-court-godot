class_name FcModalHost
extends Control
## The layer all dialogs open on. It keeps a stack: only the TOP dialog receives keys (Escape closes just that one), the ones
## beneath are paused until it closes. Everything below the layer is blocked by the dialog's own dim layer. The host itself ignores
## the mouse, so an empty host never gets in the way.

var _stack: Array[FcModal] = []


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## Opens a dialog on this layer.
func open(modal: FcModal) -> FcModal:
	if not _stack.is_empty():
		_stack.back().process_mode = Node.PROCESS_MODE_DISABLED
	_stack.append(modal)
	modal.closed.connect(func() -> void: _on_closed(modal))
	modal.open(self)
	return modal


## A confirmation dialog; `on_confirm` runs only if the player confirms. Destructive ones start on Cancel.
func confirm(title: String, text: String, on_confirm: Callable, destructive: bool = false, confirm_text: String = "Confirm") -> FcModal:
	var m := FcModal.new(title, text, FcModal.Kind.DESTRUCTIVE if destructive else FcModal.Kind.CONFIRM, confirm_text)
	m.confirmed.connect(on_confirm)
	return open(m)


## A message with one OK button.
func notice(title: String, text: String) -> FcModal:
	return open(FcModal.new(title, text, FcModal.Kind.INFO))


func count() -> int:
	return _stack.size()


func top() -> FcModal:
	return _stack.back() if not _stack.is_empty() else null


## Cancels every open dialog (for example when the app returns to the main menu).
func close_all() -> void:
	for m in _stack.duplicate():
		if is_instance_valid(m):
			m.close(false)


func _on_closed(modal: FcModal) -> void:
	_stack.erase(modal)
	if not _stack.is_empty():
		_stack.back().process_mode = Node.PROCESS_MODE_INHERIT
