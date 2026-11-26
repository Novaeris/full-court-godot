class_name FcResultBadge
extends PanelContainer
## The outcome of a game in one small badge: "W 102-99" (green), "L 95-101" (red), "FINAL" (neutral), "UPCOMING" (steel), "LIVE" (orange).
## The letter and the words carry the meaning, so it is readable without colour.

enum Kind { WIN, LOSS, FINAL, UPCOMING, LIVE }

var kind: Kind = Kind.UPCOMING
var _label := Label.new()


func _init(badge_kind: Kind = Kind.UPCOMING, text: String = "") -> void:
	_label.theme_type_variation = "NumericLabel"
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_label)
	set_result(badge_kind, text)


## `score` is shown after the letter for WIN and LOSS ("102-99").
func set_result(badge_kind: Kind, score: String = "") -> FcResultBadge:
	kind = badge_kind
	var c := color_of(badge_kind)
	var box := StyleBoxFlat.new()
	box.bg_color = Color(c, 0.2)
	box.border_color = c
	box.set_border_width_all(1)
	box.set_corner_radius_all(FcUiTokens.RADIUS_CONTROL)
	box.content_margin_left = FcUiTokens.SPACE_2
	box.content_margin_right = FcUiTokens.SPACE_2
	box.content_margin_top = 2
	box.content_margin_bottom = 2
	add_theme_stylebox_override("panel", box)
	_label.add_theme_color_override("font_color", c.lightened(0.2))
	_label.text = text_of(badge_kind, score)
	tooltip_text = {Kind.WIN: "Won", Kind.LOSS: "Lost", Kind.FINAL: "Final", Kind.UPCOMING: "Not played yet", Kind.LIVE: "In progress"}[badge_kind] + ((" " + score) if score != "" else "")
	return self


func text() -> String:
	return _label.text


static func text_of(badge_kind: Kind, score: String = "") -> String:
	match badge_kind:
		Kind.WIN: return ("W " + score).strip_edges()
		Kind.LOSS: return ("L " + score).strip_edges()
		Kind.FINAL: return "FINAL"
		Kind.LIVE: return "LIVE"
	return "UPCOMING"


static func color_of(badge_kind: Kind) -> Color:
	match badge_kind:
		Kind.WIN: return FcUiTokens.SUCCESS
		Kind.LOSS: return FcUiTokens.DANGER
		Kind.LIVE: return FcUiTokens.PRIMARY
		Kind.FINAL: return FcUiTokens.TEXT_MUTED
	return FcUiTokens.STEEL
