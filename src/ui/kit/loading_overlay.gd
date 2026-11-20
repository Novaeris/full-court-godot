class_name FcLoadingOverlay
extends ColorRect
## A dim layer with a loading indicator over a screen, for work that takes a moment (simulating a season, loading a save). It blocks
## clicks while shown. Use show_on(parent, message) and dismiss(). Phase 3 uses it for long actions (the work is deferred one
## frame so the overlay is drawn first).

var loading: FcLoading


func _init(message: String = "Loading...") -> void:
	color = FcUiTokens.SCRIM
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	loading = FcLoading.new(message)
	center.add_child(loading)


static func show_on(parent: Node, message: String = "Loading...") -> FcLoadingOverlay:
	var o := FcLoadingOverlay.new(message)
	parent.add_child(o)
	FcMotion.fade_in(o, FcUiTokens.DUR_FAST)
	return o


func dismiss() -> void:
	FcMotion.fade_out(self, FcUiTokens.DUR_FAST, true)
