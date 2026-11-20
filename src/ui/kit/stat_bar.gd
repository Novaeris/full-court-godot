class_name FcStatBar
extends VBoxContainer
## A "tale of the tape" row for comparing two sides (home and away, you and the opponent): the stat's name in the middle above,
## each side's number at the ends, and one bar split in proportion to the two values. The leading side's number is bright.
## `lower_is_better` flips who leads (turnovers). Broadcast personality; also used in card comparison.
## animate_in() grows the bar from the middle (instant when motion is reduced).

var left_value: float = 0.0
var right_value: float = 0.0
var lower_is_better: bool = false
var left_color: Color = FcUiTokens.INFO
var right_color: Color = FcUiTokens.PRIMARY
var _title := Label.new()
var _left_label := Label.new()
var _right_label := Label.new()
var _bar := _Bar.new()


func _init(title: String = "", left: float = 0.0, right: float = 0.0, left_text: String = "", right_text: String = "", lower_better: bool = false) -> void:
	lower_is_better = lower_better
	add_theme_constant_override("separation", 2)
	_title.text = title.to_upper()
	_title.theme_type_variation = "CaptionLabel"
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_title)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", FcUiTokens.SPACE_3)
	add_child(row)
	for label in [_left_label, _right_label]:
		label.theme_type_variation = "NumericLabel"
		label.custom_minimum_size.x = 56
	_left_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_right_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_bar.custom_minimum_size.y = 10
	_bar.bar = self
	row.add_child(_left_label)
	row.add_child(_bar)
	row.add_child(_right_label)
	set_values(left, right, left_text, right_text)


func set_values(left: float, right: float, left_text: String = "", right_text: String = "") -> void:
	left_value = left
	right_value = right
	_left_label.text = left_text if left_text != "" else str(roundi(left))
	_right_label.text = right_text if right_text != "" else str(roundi(right))
	var lead := leader()
	_left_label.add_theme_color_override("font_color", FcUiTokens.TEXT if lead != 1 else FcUiTokens.TEXT_MUTED)
	_right_label.add_theme_color_override("font_color", FcUiTokens.TEXT if lead != 0 else FcUiTokens.TEXT_MUTED)
	_bar.queue_redraw()


## 0 when the left side leads, 1 when the right side does, -1 when level.
func leader() -> int:
	if is_equal_approx(left_value, right_value):
		return -1
	var left_leads := left_value < right_value if lower_is_better else left_value > right_value
	return 0 if left_leads else 1


## The left side's share of the bar (0 to 1; one half when both are zero).
func left_share() -> float:
	var total := left_value + right_value
	return 0.5 if total <= 0.0 else clampf(left_value / total, 0.0, 1.0)


func animate_in() -> void:
	_bar.grow = 0.0
	FcMotion.tween_property(_bar, "grow", 1.0, FcUiTokens.DUR_SLOW * 2.0)


class _Bar extends Control:
	var bar: FcStatBar
	var grow: float = 1.0:
		set(v):
			grow = v
			queue_redraw()

	func _draw() -> void:
		if bar == null:
			return
		var gap := 2.0
		var share := bar.left_share()
		var left_w := maxf(0.0, (size.x * share - gap / 2.0))
		var right_w := maxf(0.0, size.x - size.x * share - gap / 2.0)
		# each side grows outward from the split point while animating
		var split := size.x * share
		var l := left_w * grow
		var r := right_w * grow
		# the trailing side is the same hue washed toward slate, so it never turns muddy
		var lc := bar.left_color if bar.leader() != 1 else bar.left_color.lerp(FcUiTokens.BORDER, 0.55)
		var rc := bar.right_color if bar.leader() != 0 else bar.right_color.lerp(FcUiTokens.BORDER, 0.55)
		draw_rect(Rect2(0, 0, size.x, size.y), FcUiTokens.SURFACE_RAISED)
		draw_rect(Rect2(split - gap / 2.0 - l, 0, l, size.y), lc)
		draw_rect(Rect2(split + gap / 2.0, 0, r, size.y), rc)
