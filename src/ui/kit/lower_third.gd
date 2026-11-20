class_name FcLowerThird
extends PanelContainer
## The broadcast lower-third: a title and a subtitle on a dark bar with a bold accent edge ("PLAYER OF THE GAME / Maya Okoro,
## 31 pts"). It slides in when shown (a fade when motion is reduced). The accent edge follows the theme accent unless a colour
## (a team colour) is given.

var title_label := Label.new()
var subtitle_label := Label.new()


func _init(title: String = "", subtitle: String = "") -> void:
	theme_type_variation = "LowerThirdPanel"
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 0)
	add_child(column)
	title_label.text = title   # shown as given: a name or a label is never re-cased (callers who want capitals pass them)
	title_label.theme_type_variation = "DisplayLabel"
	title_label.add_theme_font_size_override("font_size", FcUiTokens.fs(FcUiTokens.TYPE_H1))
	column.add_child(title_label)
	subtitle_label.text = subtitle
	subtitle_label.theme_type_variation = "MutedLabel"
	column.add_child(subtitle_label)
	subtitle_label.visible = subtitle != ""


## Changes the accent edge colour (for example to a team's colour).
func set_accent(color: Color) -> void:
	var base := get_theme_stylebox("panel", "LowerThirdPanel") as StyleBoxFlat
	if base == null:
		return
	var box := base.duplicate() as StyleBoxFlat
	box.border_color = FcUiContrast.ensure(color, FcUiTokens.SURFACE, 3.0)
	add_theme_stylebox_override("panel", box)


func play_in() -> void:
	FcMotion.slide_in(self, Vector2(-32, 0))
