class_name FcCelebration
extends Control
## A championship moment: a banner with a trophy and the title raised over a dimmed screen, with a burst of confetti and the championship
## fanfare. Click, any key or a few seconds dismiss it. It is feedback for a real result (the user's team won the title), never decoration:
## with reduced motion there is no confetti and no raise, just the banner and the sound. Confetti is capped (80 pieces, 40 on touch layouts)
## so it stays cheap on a phone, and it needs no texture (small coloured squares).

signal finished

const MAX_PIECES := 80
const MAX_PIECES_TOUCH := 40
const SHOW_SECONDS := 4.0

var panel: PanelContainer
var confetti: CPUParticles2D = null
var _done := false


func _init(title: String = "Champions", subtitle: String = "") -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	var scrim := ColorRect.new()
	scrim.color = FcUiTokens.SCRIM
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(scrim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	panel = PanelContainer.new()
	var box := StyleBoxFlat.new()
	box.bg_color = FcUiTokens.SURFACE_RAISED
	box.border_color = FcUiTokens.GOLD
	box.set_border_width_all(3)
	box.set_corner_radius_all(FcUiTokens.RADIUS_MODAL)
	box.set_content_margin_all(28)
	FcUiTokens.elevate(box, 3)
	panel.add_theme_stylebox_override("panel", box)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", FcUiTokens.SPACE_3)
	panel.add_child(column)
	var trophy := FcUiIcons.rect("trophy", FcUiTokens.GOLD, 64)
	trophy.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	column.add_child(trophy)
	var heading := FcUiTables.label(title, FcUiTokens.TYPE_DISPLAY_XL, true)
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(heading)
	if subtitle != "":
		var sub := FcUiTables.label(subtitle, FcUiTokens.TYPE_H3)
		sub.theme_type_variation = "MutedLabel"
		sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		column.add_child(sub)
	var hint := FcUiTables.label("Click to continue", FcUiTokens.TYPE_SMALL)
	hint.theme_type_variation = "CaptionLabel"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(hint)
	tooltip_text = "%s. %s" % [title, subtitle]


## Shows a celebration on `host` (a Control that covers the window, such as FcScreenHost.overlay) and returns it.
static func show_on(host: Control, title: String = "Champions", subtitle: String = "") -> FcCelebration:
	var c := FcCelebration.new(title, subtitle)
	host.add_child(c)
	c.start()
	return c


## How many confetti pieces this layout gets.
static func piece_count() -> int:
	return MAX_PIECES_TOUCH if FcUiTokens.touch_mode else MAX_PIECES


func start() -> void:
	FcAudio.cue("championship")
	grab_focus()
	if not FcMotion.reduced:
		FcMotion.pop_in(panel, FcUiTokens.DUR_SLOW)
		_burst()
	if is_inside_tree():
		get_tree().create_timer(SHOW_SECONDS).timeout.connect(dismiss)


func _burst() -> void:
	confetti = CPUParticles2D.new()
	confetti.amount = piece_count()
	confetti.one_shot = true
	confetti.explosiveness = 0.85
	confetti.lifetime = 3.0
	confetti.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	confetti.emission_rect_extents = Vector2(maxf(size.x, 400.0) / 2.0, 6.0)
	confetti.position = Vector2(maxf(size.x, 400.0) / 2.0, -10.0)
	confetti.direction = Vector2(0, 1)
	confetti.spread = 40.0
	confetti.gravity = Vector2(0, 520)
	confetti.initial_velocity_min = 120.0
	confetti.initial_velocity_max = 320.0
	confetti.angular_velocity_min = -240.0
	confetti.angular_velocity_max = 240.0
	confetti.scale_amount_min = 4.0
	confetti.scale_amount_max = 9.0
	var ramp := Gradient.new()
	var colors := PackedColorArray(FcUiTokens.CHART)
	ramp.offsets = PackedFloat32Array([0.0, 1.0])
	ramp.colors = PackedColorArray([colors[0], colors[3]])
	confetti.color_initial_ramp = ramp
	add_child(confetti)
	confetti.emitting = true


func _gui_input(event: InputEvent) -> void:
	if (event is InputEventMouseButton or event is InputEventKey or event is InputEventScreenTouch) and event.pressed:
		accept_event()
		dismiss()


func dismiss() -> void:
	if _done:
		return
	_done = true
	finished.emit()
	FcMotion.fade_out(self, FcUiTokens.DUR_BASE, true)
