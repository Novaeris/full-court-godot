class_name FcStatLine
extends HBoxContainer
## One "label ... value" row: the label muted on the left, the value in tabular figures on the right (so numbers line up in a
## column). Used in compact tables, player profiles and result panels. `emphasis` draws the value in the heading colour.

var label_node := Label.new()
var value_node := Label.new()


func _init(label_text: String = "", value_text: String = "", emphasis: bool = false) -> void:
	label_node.text = label_text
	label_node.theme_type_variation = "MutedLabel"
	label_node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label_node.clip_text = true
	label_node.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	value_node.text = value_text
	value_node.theme_type_variation = "NumericLabel"
	value_node.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	if emphasis:
		value_node.add_theme_color_override("font_color", FcUiTokens.GOLD)
	add_child(label_node)
	add_child(value_node)


static func make(label_text: String, value_text: String, emphasis: bool = false) -> FcStatLine:
	return FcStatLine.new(label_text, value_text, emphasis)
