class_name FcScreenHost
extends Control
## The frame every screen lives in: the backdrop (flat, a faint grid for Broadcast, a spotlight for Collectible: chosen by the mode
## skin), the safe-area margins, the `content` column the current screen fills, and the overlay layer above it with the dialogs
## (`modals`), the toasts (`toasts`) and loading overlays. It owns no game logic and no screen: FcApp puts screens in `content`.
## `content` sits in a scroll area: a screen that is wider than the window scrolls sideways instead of being clipped (Owner and Career
## screens in a small window, D6). The bottom bar (the mobile navigation) is part of the frame, so it always spans the window.

const BASE_MARGIN := 16
const BOTTOM_BAR_HEIGHT := 68
const MAX_CONTENT_WIDTH := 1600

var content: VBoxContainer
var bottom_slot: VBoxContainer
var modals: FcModalHost
var toasts: FcToastStack
var overlay: Control
var _backdrop := _Backdrop.new()
var _margin := MarginContainer.new()
var _scroll := ScrollContainer.new()
var _frame := VBoxContainer.new()
var _safe := {"left": 0, "top": 0, "right": 0, "bottom": 0}


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_backdrop)
	_frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_frame.add_theme_constant_override("separation", 0)
	add_child(_frame)
	_margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_frame.add_child(_margin)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_margin.add_child(_scroll)
	content = VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL   # a ScrollContainer only stretches a child that asks to expand
	content.add_theme_constant_override("separation", 10)
	_scroll.add_child(content)
	bottom_slot = VBoxContainer.new()
	_frame.add_child(bottom_slot)
	overlay = Control.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(overlay)
	toasts = FcToastStack.new()
	overlay.add_child(toasts)
	modals = FcModalHost.new()
	overlay.add_child(modals)
	set_safe_margins(_safe)


## Applies a device safe area (see FcLayoutProfile.safe_margins) on top of the normal 16 px margin. On a very wide window the sides
## also grow so the content stays at most MAX_CONTENT_WIDTH wide and centred (ultrawide screens, 21:9 and wider).
func set_safe_margins(margins: Dictionary) -> void:
	_safe = margins
	var extra := side_padding(size.x)
	for side in ["left", "top", "right", "bottom"]:
		var more := extra if side == "left" or side == "right" else 0
		_margin.add_theme_constant_override("margin_" + side, BASE_MARGIN + int(margins.get(side, 0)) + more)
	set_toast_inset(0)


## Extra pixels to add to each side so content never gets wider than MAX_CONTENT_WIDTH. Zero for any normal window.
static func side_padding(window_width: float) -> int:
	return maxi(0, int((window_width - MAX_CONTENT_WIDTH) / 2.0))


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and toasts != null:
		set_safe_margins(_safe)


## Puts a control along the bottom edge of the window (the mobile navigation bar), above the safe-area margin, and lifts the toasts
## above it. Pass null to remove it.
func set_bottom_bar(bar: Control) -> void:
	for c in bottom_slot.get_children():
		bottom_slot.remove_child(c)
		c.queue_free()
	if bar != null:
		bottom_slot.add_child(bar)
		var home_indicator := Control.new()   # keeps the bar clear of a phone's home indicator (the safe area)
		home_indicator.custom_minimum_size.y = int(_safe.get("bottom", 0))
		bottom_slot.add_child(home_indicator)
	set_toast_inset(BOTTOM_BAR_HEIGHT if bar != null else 0)


## Keeps toasts clear of something along the bottom edge (the mobile navigation bar), in pixels.
func set_toast_inset(pixels: int) -> void:
	toasts.offset_bottom = -(FcUiTokens.SPACE_4 + int(_safe.get("bottom", 0)) + pixels)
	toasts.offset_top = toasts.offset_bottom - 220


## The mode skin's backdrop: "flat", "grid" or "spotlight", tinted by the skin's accent.
func set_skin(skin: Dictionary) -> void:
	_backdrop.style = str(skin.get("background", "flat"))
	_backdrop.accent = skin.get("accent", FcUiTokens.PRIMARY)
	_backdrop.queue_redraw()


func backdrop_style() -> String:
	return _backdrop.style


## Fades a freshly built screen in (instant when motion is reduced).
func transition_in(screen: CanvasItem) -> void:
	FcMotion.fade_in(screen, FcUiTokens.DUR_BASE)


## Draws the background.
class _Backdrop extends Control:
	var style: String = "flat"
	var accent: Color = FcUiTokens.PRIMARY
	var _glow: GradientTexture2D = null

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), FcUiTokens.BG)
		match style:
			"grid":
				var line := Color(FcUiTokens.BORDER, 0.28)
				var x := 0.0
				while x < size.x:
					draw_line(Vector2(x, 0), Vector2(x, size.y), line, 1.0)
					x += 48.0
				var y := 0.0
				while y < size.y:
					draw_line(Vector2(0, y), Vector2(size.x, y), line, 1.0)
					y += 48.0
			"spotlight":
				if _glow == null:
					_glow = GradientTexture2D.new()
					_glow.fill = GradientTexture2D.FILL_RADIAL
					_glow.fill_from = Vector2(0.5, 0.0)
					_glow.fill_to = Vector2(0.5, 1.0)
					_glow.width = 256
					_glow.height = 256
				var g := Gradient.new()
				g.set_color(0, Color(accent, 0.16))
				g.set_color(1, Color(accent, 0.0))
				_glow.gradient = g
				draw_texture_rect(_glow, Rect2(Vector2.ZERO, size), false)

	func _notification(what: int) -> void:
		if what == NOTIFICATION_RESIZED:
			queue_redraw()
