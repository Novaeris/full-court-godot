class_name FcToastStack
extends VBoxContainer
## Where toasts appear: a column at the bottom centre of its parent (it ignores the mouse, so it never blocks the screen).
## push() shows a toast for a few seconds; at most MAX_VISIBLE are shown (the oldest goes first) and a message that is already
## showing just restarts its timer instead of stacking. Phase 3 wires this up as the app-wide notifier.

const MAX_VISIBLE := 3

var _entries: Array = []   # [{toast, timer}]


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	alignment = BoxContainer.ALIGNMENT_END
	add_theme_constant_override("separation", FcUiTokens.SPACE_2)
	set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	offset_top = -220
	offset_bottom = -FcUiTokens.SPACE_4
	offset_left = FcUiTokens.SPACE_4
	offset_right = -FcUiTokens.SPACE_4


## Shows a message. Returns the toast.
func push(kind: FcToast.Kind, text: String) -> FcToast:
	for entry in _entries:
		var existing: FcToast = entry["toast"]
		if is_instance_valid(existing) and existing.kind == kind and existing.message == text:
			var again: Timer = entry["timer"]
			if again.is_inside_tree():
				again.start(FcToast.hold_seconds(kind, text.length()))
			return existing
	while _entries.size() >= MAX_VISIBLE:
		_remove(_entries[0])
	var toast := FcToast.new(kind, text)
	var timer := Timer.new()
	timer.one_shot = true
	timer.autostart = true   # starts when the toast enters the tree (so a stack that is not on screen yet makes no noise)
	timer.wait_time = FcToast.hold_seconds(kind, text.length())
	var entry := {"toast": toast, "timer": timer}
	_entries.append(entry)
	toast.add_child(timer)
	timer.timeout.connect(func() -> void: _remove(entry))
	toast.dismissed.connect(func() -> void: _entries.erase(entry))
	add_child(toast)
	FcMotion.fade_in(toast)
	return toast


func visible_count() -> int:
	return _entries.size()


func clear() -> void:
	for entry in _entries.duplicate():
		_remove(entry)


func _remove(entry: Dictionary) -> void:
	_entries.erase(entry)
	var toast: FcToast = entry["toast"]
	if is_instance_valid(toast) and not toast.is_queued_for_deletion():
		FcMotion.fade_out(toast, FcUiTokens.DUR_BASE, true)
