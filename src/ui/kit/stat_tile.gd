class_name FcStatTile
extends PanelContainer
## A headline number with its label and an optional change ("+3" in green, "-2" in red): a KPI, a record, a reward total.
## `kpi` gives it the Franchise look (an accent bar on top); otherwise it is a plain raised tile.

var label_node := Label.new()
var value_node := Label.new()
var delta_node := Label.new()


func _init(label_text: String = "", value_text: String = "", delta_text: String = "", kpi: bool = false) -> void:
	theme_type_variation = "KpiPanel" if kpi else "RaisedPanel"
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 2)
	add_child(column)
	label_node.text = label_text.to_upper()
	label_node.theme_type_variation = "CaptionLabel"
	label_node.add_theme_font_size_override("font_size", FcUiTokens.fs(FcUiTokens.TYPE_MICRO + 1))
	column.add_child(label_node)
	value_node.text = value_text
	value_node.theme_type_variation = "DisplayLabel"
	value_node.add_theme_font_size_override("font_size", FcUiTokens.fs(FcUiTokens.TYPE_DISPLAY))
	column.add_child(value_node)
	column.add_child(delta_node)
	set_delta(delta_text)


func set_value(text: String) -> void:
	value_node.text = text


## A change such as "+3" or "-2.5": green when it starts with + (or is an up arrow), red when it starts with - (or a down arrow).
func set_delta(text: String) -> void:
	delta_node.text = text
	delta_node.visible = text != ""
	var up := text.begins_with("+") or text.begins_with("▲")
	var down := text.begins_with("-") or text.begins_with("▼")
	delta_node.add_theme_color_override("font_color", FcUiTokens.SUCCESS if up else (FcUiTokens.DANGER if down else FcUiTokens.TEXT_MUTED))
	delta_node.add_theme_font_size_override("font_size", FcUiTokens.fs(FcUiTokens.TYPE_SMALL))


static func make(label_text: String, value_text: String, delta_text: String = "", kpi: bool = false) -> FcStatTile:
	return FcStatTile.new(label_text, value_text, delta_text, kpi)
